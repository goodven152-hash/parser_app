import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'cron_editor.dart';
import 'dart:html' as html;

/// Flutter-Web админка к парсеру GETenders.
/// Покрывает API:
///   • POST /run, POST /run/stop            — запуск / остановка
///   • WS  /ws                             — live-лог
///   • GET /runs /next_run /schedule       — история, план, cron
///   • PUT /schedule                       — изменяет cron
///   • GET/PUT /config /keywords           — правка конфига и ключевых слов
///   • GET /run/{id}/log|result            — лог и JSON результата

// ──────────────────────────────────────────────────────────────────────

/// ─────────────────────────────────────────────
/// 1.  Единственный хард-код для доступа
const _password = "^tZt)1A6h/(hYXc]/486'4[g";
const _sessKey = 'parser_admin_login_ts';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Parser Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
    home: const _Gate(), // "роутер" между логином и UI
  );
}

// ─────────────────────────────────────────────
/// 2.  Простейший стейт-фул «роутер»
class _Gate extends StatefulWidget {
  const _Gate({super.key});
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _loggedIn = false;
  void _onLoginOk() => setState(() => _loggedIn = true);

  @override
  void initState() {
    super.initState();
    final tsStr = html.window.localStorage[_sessKey];
    if (tsStr != null) {
      final ts = int.tryParse(tsStr);
      if (ts != null && DateTime.now().millisecondsSinceEpoch - ts < 3600 * 1000) {
        _loggedIn = true;
      } else {
        html.window.localStorage.remove(_sessKey);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _Gate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loggedIn) {
      html.window.localStorage[_sessKey] = DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  @override
  Widget build(BuildContext context) =>
      _loggedIn ? const HomePage() : LoginPage(onSuccess: _onLoginOk);
}

// ─────────────────────────────────────────────
/// 3.  Страница логина
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSuccess});
  final VoidCallback onSuccess;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _ctrl = TextEditingController();
  String? _err;

  void _tryLogin() {
    if (_ctrl.text == _password) {
      html.window.localStorage[_sessKey] =
          DateTime.now().millisecondsSinceEpoch.toString();
      widget.onSuccess();
    } else {
      setState(() => _err = 'Неверный пароль');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Admin Login',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: _err,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _tryLogin(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _tryLogin,
                    child: const Text('Enter'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uri _u(String path) => Uri.parse('http://${Uri.base.host}:8000$path');

  // live state via WS
  final _ws = WebSocketChannel.connect(
    Uri.parse('ws://${Uri.base.host}:8000/ws'),
  );
  String? _runId;
  double _progress = 0;
  final List<String> _liveLog = [];

  // polled data
  List<Map<String, dynamic>> _runs = [];
  List<String> _keywords = [];
  bool _keywordsDirty = false;
  DateTime? _nextUtc;
  String _cronStr = "";

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _ws.stream.listen((raw) {
      final data = json.decode(raw);
      final id = data['id'] as String?;
      final lines = List<String>.from(data['lines'] ?? []);
      if (!mounted) return;
      setState(() {
        if (id != null) {
          // ── активный запуск ───────────
          if (_runId != id) {
            _runId = id;
            _liveLog.clear();
          }
          _progress = (data['progress'] as num).toDouble() / 100.0;
          _liveLog.addAll(lines);
        } else if (_runId != null) {
          // ── запуск завершён ───────────
          _runId = null;
          _progress = 0;
          _liveLog.clear();
        }
      });
    });
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _refreshAll());
  }

  @override
  void dispose() {
    _ws.sink.close();
    _ticker?.cancel();
    super.dispose();
  }

  // ───────── API helpers ─────────
  Future<void> _refreshAll() async {
    await Future.wait([
      _fetchRuns(),
      _fetchKeywords(),
      _fetchNextRun(),
      _fetchCron(),
    ]);
  }

  Future<void> _fetchRuns() async {
    final r = await http.get(_u('/runs'));
    if (r.statusCode == 200) {
      setState(
        () => _runs = List<Map<String, dynamic>>.from(json.decode(r.body)),
      );
    }
  }

  Future<void> _fetchKeywords() async {
    if (_keywordsDirty) return;
    final r = await http.get(_u('/keywords'));
    if (r.statusCode == 200) {
      setState(
        () => _keywords = List<String>.from(json.decode(r.body)['KEYWORDS_GEO']),
      );
    }
  }

  Future<void> _fetchNextRun() async {
    final r = await http.get(_u('/next_run'));
    if (r.statusCode == 200) {
      final iso = json.decode(r.body)['next'] as String?;
      if (iso != null) setState(() => _nextUtc = DateTime.parse(iso).toLocal());
    }
  }

  Future<void> _fetchCron() async {
    final r = await http.get(_u('/schedule'));
    if (r.statusCode == 200) {
      setState(() => _cronStr = json.decode(r.body)['cron']);
    }
  }

  Future<void> _triggerRun() async => http.post(_u('/run'));
  Future<void> _stopRun() async => http.post(_u('/run/stop'));

  Future<void> _saveKeywords() async {
    await http.put(
      _u('/keywords'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(_keywords),
    );
    _keywordsDirty = false;
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Keywords saved')));
    }
  }

  Future<void> _editConfig() async {
    final r = await http.get(_u('/config'));
    if (r.statusCode != 200) return;
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(json.decode(r.body)),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit config.json'),
            content: SizedBox(
              width: 600,
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.0,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (ok == true) {
      try {
        final cfg = json.decode(controller.text);
        await http.put(
          _u('/config'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(cfg),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Config saved')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('JSON error: $e')));
        }
      }
    }
  }

  Future<void> _editCron() async {
    final expr = await showCronEditor(context, initial: _cronStr);
    if (expr == null) return;
    final res = await http.put(
      _u('/schedule'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({"cron": expr}),
    );
    if (res.statusCode == 200) {
      _fetchNextRun();
      setState(() => _cronStr = expr);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid cron: ${res.body}')));
    }
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Parser Admin')),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // action row
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _triggerRun,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run now'),
                ),
                const SizedBox(width: 8),
                if (_runId != null) // Stop only when running
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _stopRun,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _editConfig,
                  icon: const Icon(Icons.settings),
                  label: const Text('Edit config'),
                ),
                const SizedBox(width: 24),
                if (_runId != null) ...[
                  Expanded(child: LinearProgressIndicator(value: _progress)),
                  const SizedBox(width: 8),
                  Text('${(_progress * 100).toStringAsFixed(0)} %'),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_nextUtc != null)
                  Text(
                    'Next run: ${_fmt(_nextUtc!)}',
                    style: th.textTheme.bodyMedium,
                  ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _editCron,
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Edit schedule'),
                ),
              ],
            ),

            if (_runId != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Console'),
                children: [
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        itemCount: _liveLog.length,
                        itemBuilder:
                            (_, i) => Text(
                              _liveLog[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: 32),
            // runs table
            Text('Last runs', style: th.textTheme.titleMedium),
            const SizedBox(height: 8),
            _runs.isEmpty
                ? const Text('no runs yet')
                : DataTable(
                  columnSpacing: 12,
                  headingRowHeight: 28,
                  dataRowMinHeight: 32,
                  columns: const [
                    DataColumn(label: Text('Start')),
                    DataColumn(label: Text('End')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: _runs.map(_row).toList(),
                ),
            const Divider(height: 32),
            // keywords
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Keywords', style: th.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _keywords.add('')),
                ),
              ],
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _keywords.length,
              onReorder: (o, n) {
                setState(() {
                  if (n > o) n -= 1;
                  final v = _keywords.removeAt(o);
                  _keywords.insert(n, v);
                  _keywordsDirty = true;
                });
              },
              itemBuilder:
                  (_, i) => ListTile(
                    key: ValueKey('kw_$i'),
                    title: TextFormField(
                      initialValue: _keywords[i],
                      onChanged: (v) {
                        _keywords[i] = v;
                        _keywordsDirty = true;
                      },
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _keywords.removeAt(i)),
                    ),
                  ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveKeywords,
                icon: const Icon(Icons.save),
                label: const Text('Save keywords'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _row(Map<String, dynamic> r) {
    final started =
        r['started'] != null ? DateTime.parse(r['started']).toLocal() : null;
    final finished =
        r['finished'] != null ? DateTime.parse(r['finished']).toLocal() : null;
    final rc = r['returncode'] as int?;
    late final IconData icon;
    late final Color color;
    late final String label;
    if (rc == 0) {
      icon = Icons.check_circle;
      color = Colors.green;
      label = 'OK';
    } else if (rc == null || rc < 0) {
      icon = Icons.pause_circle_filled;
      color = Colors.grey;
      label = 'Stopped';
    } else {
      icon = Icons.error;
      color = Colors.red;
      label = 'Error';
    }
    return DataRow(
      onSelectChanged:
          (_) => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => RunDetailsPage(runId: r['id'] as String, base: _u('')),
            ),
          ),
      cells: [
        DataCell(Text(started != null ? _fmt(started) : '-')),
        DataCell(Text(finished != null ? _fmt(finished) : '-')),
        DataCell(
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) =>
      '${_2(dt.day)}/${_2(dt.month)}/${dt.year} ${_2(dt.hour)}:${_2(dt.minute)}';
  String _2(int n) => n.toString().padLeft(2, '0');
}

// ──────────────────────────────────────────────────────────────────────
class RunDetailsPage extends StatefulWidget {
  const RunDetailsPage({super.key, required this.runId, required this.base});
  final String runId;
  final Uri base;
  @override
  State createState() => _RunDetailsPageState();
}

class _RunDetailsPageState extends State<RunDetailsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  String? _log, _resultJson;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logUri = widget.base.replace(path: '/run/${widget.runId}/log');
    final resUri = widget.base.replace(path: '/run/${widget.runId}/result');
    final l = await http.get(logUri);
    if (l.statusCode == 200) setState(() => _log = l.body);
    final r = await http.get(resUri);
    if (r.statusCode == 200) {
      setState(
        () =>
            _resultJson = const JsonEncoder.withIndent(
              '  ',
            ).convert(json.decode(r.body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Run ${widget.runId.substring(0, 8)}'),
      bottom: TabBar(
        controller: _tab,
        tabs: const [Tab(text: 'Log'), Tab(text: 'Result')],
      ),
    ),
    body: TabBarView(
      controller: _tab,
      children: [
        _log == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
        _resultJson == null
            ? const Center(child: Text('Result not found'))
            : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _resultJson!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
      ],
    ),
  );
}
