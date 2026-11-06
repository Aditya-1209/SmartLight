import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scene.dart';

String sceneTurnOffLabel(BuildContext context, SceneOffSchedule schedule) =>
    schedule.mode == SceneOffMode.after
    ? 'Off after ${schedule.minutes % 60 == 0 ? '${schedule.minutes ~/ 60} ${schedule.minutes == 60 ? 'hour' : 'hours'}' : '${schedule.minutes} min'}'
    : 'Off at ${TimeOfDay(hour: schedule.hour, minute: schedule.minute).format(context)}';

class SceneTimingEditor extends StatefulWidget {
  const SceneTimingEditor({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final SceneOffSchedule? value;
  final ValueChanged<SceneOffSchedule?> onChanged;
  final bool enabled;
  @override
  State<SceneTimingEditor> createState() => _SceneTimingEditorState();
}

class _SceneTimingEditorState extends State<SceneTimingEditor> {
  late final TextEditingController _minutes;
  late String _mode;
  late TimeOfDay _time;
  @override
  void initState() {
    super.initState();
    _minutes = TextEditingController(
      text:
          '${widget.value?.mode == SceneOffMode.after ? widget.value!.minutes : 30}',
    );
    _mode = widget.value?.mode.name ?? 'none';
    _time = widget.value?.mode == SceneOffMode.at
        ? TimeOfDay(hour: widget.value!.hour, minute: widget.value!.minute)
        : TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _emit() {
    setState(() {});
    final minutes = int.tryParse(_minutes.text);
    widget.onChanged(
      _mode == 'none'
          ? null
          : _mode == 'at'
          ? SceneOffSchedule.at(_time.hour, _time.minute)
          : minutes != null && minutes >= 1 && minutes <= 1440
          ? SceneOffSchedule.after(minutes)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Turn off automatically',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text('Set a turn-off time whenever you apply this scene.'),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'none', label: Text('None')),
          ButtonSegment(value: 'after', label: Text('After a delay')),
          ButtonSegment(value: 'at', label: Text('At a time')),
        ],
        selected: {_mode},
        onSelectionChanged: widget.enabled
            ? (value) {
                _mode = value.first;
                _emit();
              }
            : null,
      ),
      if (_mode == 'after') ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in [15, 30, 60, 120])
              ChoiceChip(
                label: Text(
                  minutes < 60
                      ? '$minutes min'
                      : '${minutes ~/ 60} ${minutes == 60 ? 'hour' : 'hours'}',
                ),
                selected: int.tryParse(_minutes.text) == minutes,
                onSelected: widget.enabled
                    ? (_) {
                        _minutes.text = '$minutes';
                        _emit();
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('scene-off-minutes'),
          controller: _minutes,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Turn off after',
            suffixText: 'min',
            helperText: '1–1,440 minutes (up to 24 hours)',
          ),
          onChanged: (_) => _emit(),
          validator: (_) {
            final value = int.tryParse(_minutes.text);
            return value == null || value < 1 || value > 1440
                ? 'Enter 1–1,440 minutes.'
                : null;
          },
        ),
      ],
      if (_mode == 'at') ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('scene-off-time'),
          icon: const Icon(Icons.schedule),
          label: Text('Turn off at ${_time.format(context)}'),
          onPressed: !widget.enabled
              ? null
              : () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (!mounted || time == null) return;
                  _time = time;
                  _emit();
                },
        ),
        const SizedBox(height: 6),
        const Text(
          'Uses the next occurrence of this time when you apply the scene.',
        ),
      ],
      if (_mode != 'none') ...[
        const SizedBox(height: 12),
        const Text(
          'Only lights this scene turns on get a new timer. Existing countdowns on those lights are replaced. Keep wall switches on; supported timers work with the app closed.',
        ),
      ],
    ],
  );
}
