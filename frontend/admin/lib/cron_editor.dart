import 'package:flutter/material.dart';

/// Returns cron expression chosen by user or null if canceled.
Future<String?> showCronEditor(BuildContext context, {required String initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CronDialog(initial: initial),
  );
}

class _CronDialog extends StatefulWidget {
  const _CronDialog({required this.initial});
  final String initial;
  @override
  State<_CronDialog> createState() => _CronDialogState();
}

enum _Freq { minutes, hours, daily, weekly, monthly, custom }

class _CronDialogState extends State<_CronDialog> {
  _Freq _freq = _Freq.daily;
  int _nMin = 5;
  int _nHour = 1;
  TimeOfDay _time = const TimeOfDay(hour: 2, minute: 0);
  int _weekday = 1; // Monday 1-7
  int _monthDay = 1;
  String _custom = '';

  @override
  void initState() {
    super.initState();
    _custom = widget.initial;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Schedule run'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<_Freq>(
                value: _freq,
                onChanged: (v) => setState(() => _freq = v!),
                items: const [
                  DropdownMenuItem(value: _Freq.minutes, child: Text('Every N minutes')),
                  DropdownMenuItem(value: _Freq.hours, child: Text('Every N hours')),
                  DropdownMenuItem(value: _Freq.daily, child: Text('Daily at time')),
                  DropdownMenuItem(value: _Freq.weekly, child: Text('Weekly')),
                  DropdownMenuItem(value: _Freq.monthly, child: Text('Monthly')),
                  DropdownMenuItem(value: _Freq.custom, child: Text('Custom cron')),
                ],
              ),
              const SizedBox(height: 12),
              if (_freq == _Freq.minutes)
                Row(children: [
                  const Text('Every'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: '$_nMin',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _nMin = int.tryParse(v) ?? _nMin,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('minutes'),
                ]),
              if (_freq == _Freq.hours)
                Row(children: [
                  const Text('Every'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: '$_nHour',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _nHour = int.tryParse(v) ?? _nHour,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('hours'),
                ]),
              if (_freq == _Freq.daily)
                ListTile(
                  title: const Text('Time'),
                  subtitle: Text(_time.format(context)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              if (_freq == _Freq.weekly) ...[
                DropdownButton<int>(
                  value: _weekday,
                  onChanged: (v) => setState(() => _weekday = v!),
                  items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][i]))),
                ),
                ListTile(
                  title: const Text('Time'),
                  subtitle: Text(_time.format(context)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ],
              if (_freq == _Freq.monthly) ...[
                Row(children: [
                  const Text('Day'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: '$_monthDay',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _monthDay = int.tryParse(v) ?? _monthDay,
                    ),
                  ),
                ]),
                ListTile(
                  title: const Text('Time'),
                  subtitle: Text(_time.format(context)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ],
              if (_freq == _Freq.custom)
                TextField(
                  controller: TextEditingController(text: _custom),
                  onChanged: (v) => _custom = v,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _buildExpr()),
            child: const Text('Save'),
          ),
        ],
      );

  String _buildExpr() {
    switch (_freq) {
      case _Freq.minutes:
        return "*/$_nMin * * * *";
      case _Freq.hours:
        return "0 */$_nHour * * *";
      case _Freq.daily:
        return "${_time.minute} ${_time.hour} * * *";
      case _Freq.weekly:
        return "${_time.minute} ${_time.hour} * * $_weekday";
      case _Freq.monthly:
        return "${_time.minute} ${_time.hour} $_monthDay * *";
      case _Freq.custom:
        return _custom.trim();
    }
  }
} 