from fastapi import FastAPI, WebSocket, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse,FileResponse, PlainTextResponse
from apscheduler.schedulers.background import BackgroundScheduler
import runner, json, datetime, asyncio, pathlib, os
from apscheduler.triggers.cron import CronTrigger
from starlette.websockets import WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from croniter import croniter, CroniterBadCronError   # pip install croniter
from zoneinfo import ZoneInfo


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # откуда разрешаем
    allow_credentials=True,                   # если нужны cookies / auth-заголовки
    allow_methods=["*"],                      # какие HTTP-методы
    allow_headers=["*"],                      # и какие заголовки принимать
)
scheduler=BackgroundScheduler(); scheduler.start()


CRON_FILE = pathlib.Path("/app/cron.txt")
if not CRON_FILE.exists():
    CRON_FILE.write_text("0 2 * * *")

_cron_expr: str = CRON_FILE.read_text().strip()

# определяем часовой пояс сервера (по systemd), по умолчанию Asia/Tbilisi
SERVER_TZ = ZoneInfo(os.environ.get("SERVER_TZ", "Asia/Tbilisi"))

# ── helper to (re)register cron job ────────────────────────────
def _schedule_job():
    trig = CronTrigger.from_crontab(_cron_expr, timezone=SERVER_TZ)
    scheduler.add_job(runner.start_run,
                      trig,
                      id="parser_job",
                      replace_existing=True)

# первичное планирование
_schedule_job()

# ── остановка текущего запуска ────────────────────────────
@app.post("/run/stop")
def stop():
    if runner.stop_run():
        return {"stopped": True}
    raise HTTPException(status_code=400, detail="No active run")


# ── чтение / изменение cron-строки ────────────────────────
@app.get("/schedule")
def get_schedule():
    return {"cron": _cron_expr}

@app.put("/schedule")
def set_schedule(body: dict):
    expr = body.get("cron", "")
    try:
        croniter(expr)              # валидация
    except CroniterBadCronError as e:
        raise HTTPException(status_code=422, detail=str(e))
    global _cron_expr
    _cron_expr = expr
    CRON_FILE.write_text(_cron_expr)
    _schedule_job()                    # пересоздаём джобу под новый cron
    return {"saved": True}

# -------- ACTIONS ----------------------------------------------------------
@app.post("/run")
def run():
    return {"run_id": runner.start_run()}

@app.get("/runs")
def recent():
    return runner.last_runs()


@app.get("/run/{run_id}/log")
def run_log(run_id: str):
    r = next((x for x in runner.last_runs(100) if x["id"] == run_id), None)
    return PlainTextResponse(r["log"] if r else "run_id not found")

@app.get("/run/{run_id}/result")
def run_result(run_id: str):
    fp = runner.LOG_DIR / f"{run_id}.json"
    if fp.exists():
        return FileResponse(fp, media_type="application/json", filename=f"{run_id}.json")
    return JSONResponse({"error": "result not found"}, status_code=404)

@app.websocket("/ws")
async def ws(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            # формируем пакет в каждом цикле
            payload = {
                "id": runner._current["id"],
                "progress": runner._current["progress"],
                "lines": []
            }
            # выгребаем накопившиеся строки лога
            while not runner._current["log"].empty():
                payload["lines"].append(runner._current["log"].get())

            # отправляем каждую секунду — фронту нужно знать, что run завершился
            await websocket.send_json(payload)

            await asyncio.sleep(1)
    except WebSocketDisconnect:
        # клиент закрыл соединение — завершаем цикл без стектрейса
        pass                             # молча выходим

# -------- CONFIG & KEYWORDS -----------------------------------------------
CONF_PATH = pathlib.Path("/app/config.json")

@app.get("/config")
def get_config():
    return json.loads(CONF_PATH.read_text())

@app.put("/config")
def update_config(cfg: dict):
    CONF_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
    return {"status":"saved"}

@app.get("/keywords")
def kw():
    return {"KEYWORDS_GEO": get_config()["KEYWORDS_GEO"]}

@app.put("/keywords")
def kw_update(kw: list[str]):
    cfg=get_config()
    cfg["KEYWORDS_GEO"]=kw
    update_config(cfg)
    return {"status":"saved"}

def _calc_next_run():
    trig = CronTrigger.from_crontab(_cron_expr, timezone=SERVER_TZ)
    return trig.get_next_fire_time(None, datetime.datetime.now(SERVER_TZ))

@app.get("/next_run")
def next_run():
    return {"next": _calc_next_run()}
