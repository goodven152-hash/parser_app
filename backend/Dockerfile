# ---------- BUILD STAGE ----------------------------------------------------
FROM python:3.12-slim AS build
WORKDIR /build

# 1. system deps (одним RUN слоем)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        chromium chromium-driver fonts-liberation \
        libasound2 libatk-bridge2.0-0 libnspr4 libnss3 \
        libx11-6 libxcomposite1 libxdamage1 libxrandr2 \
        libgbm1 libxss1 libxtst6 libgtk-3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. backend requirements → wheels
COPY backend/requirements.txt backend-requirements.txt  
RUN pip wheel -r backend-requirements.txt --wheel-dir /wheels

# 3. clone parser and build its wheels
RUN git clone --branch tested_branch \
      https://github.com/goodven152/parser_GETenders.git /opt/parser && \
    pip wheel -r /opt/parser/requirements.txt --wheel-dir /wheels && \
    rm -rf /opt/parser/.git          # убрать историю, чтобы не тащить в final

# ---------- RUNTIME STAGE --------------------------------------------------
FROM python:3.12-slim
WORKDIR /app

# env tweaks для экономии RAM / ускорения pip
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    CHROME_BINARY=/usr/bin/chromium-browser \
    CHROMEDRIVER=/usr/bin/chromedriver \
    PATH="$PATH:/usr/bin"

# system chrome + libs             (дублируем, но slim-слой общий, поэтому кеш)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        chromium chromium-driver fonts-liberation \
        libasound2 libatk-bridge2.0-0 libnspr4 libnss3 \
        libx11-6 libxcomposite1 libxdamage1 libxrandr2 \
        libgbm1 libxss1 libxtst6 libgtk-3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 1. устанавливаем все wheels (backend + parser)
COPY --from=build /wheels /tmp/wheels
COPY --from=build /build/backend-requirements.txt /tmp/backend-requirements.txt
COPY --from=build /opt/parser/requirements.txt /tmp/parser-requirements.txt
RUN pip install --no-index --find-links=/tmp/wheels \
        -r /tmp/backend-requirements.txt \
        -r /tmp/parser-requirements.txt && \
    rm -rf /tmp/wheels /tmp/backend-requirements.txt /tmp/parser-requirements.txt

# 2. копируем исходники backend-API
COPY backend /app
# 3. копируем исходники парсера (уже без .git)
COPY --from=build /opt/parser /opt/parser
ENV PYTHONPATH="/opt/parser:${PYTHONPATH}"

# 4. заранее скачиваем грузинскую модель stanza (по желанию +~ 400 МБ)
RUN python - <<'PY'
import stanza, os
stanza.download('ka', processors='tokenize,mwt,pos,lemma')
PY

# --------- ENTRYPOINT ------------------------------------------------------
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
