import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/light_timer.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../widgets/common.dart';

void openTimers(BuildContext context, {String? slotId}) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (_) => TimersScreen(initialSlotId: slotId),
      ),
    );

class TimersScreen extends ConsumerStatefulWidget {
  const TimersScreen({super.key, this.initialSlotId});
  final String? initialSlotId;
  @override
  ConsumerState<TimersScreen> createState() => _TimersScreenState();
}

class _TimersScreenState extends ConsumerState<TimersScreen>
    with WidgetsBindingObserver {
  final _minutes = TextEditingController(text: '30');
  final _selected = <String>{};
  Map<String, LightTimerStatus> _statuses = {};
  Map<String, String> _errors = {};
  Timer? _refresh;
  bool _loading = true, _saving = false, _atTime = false, _on = false;
  bool _foreground = true, _firstLoad = true;
  int _loadVersion = 0;
  DateTime? _scheduledAt;
  ActionReport? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _minutes.addListener(_inputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground &&
          !_saving &&
          !_loading &&
          ModalRoute.of(context)?.isCurrent == true) {
        _load();
      }
    });
  }

  void _inputChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final wasBackground = !_foreground;
      _foreground = true;
      if (wasBackground) _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      ++_loadVersion;
      // A cached timer is never presented as fresh after returning to the app.
      setState(() {
        _statuses = {};
        _errors = {};
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_foreground) return;
    final version = ++_loadVersion;
    setState(() => _loading = true);
    final controller = ref.read(appControllerProvider.notifier);
    final slots = ref.read(appControllerProvider).slots;
    final statuses = <String, LightTimerStatus>{};
    final errors = <String, String>{};
    await Future.wait(
      slots.map((slot) async {
        try {
          statuses[slot.id] = await controller.readTimer(slot.id);
        } catch (error) {
          errors[slot.id] = userMessage(error);
        }
      }),
    );
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _statuses = statuses;
      _errors = errors;
      _loading = false;
      if (_firstLoad) {
        for (final slot in slots) {
          if ((widget.initialSlotId == null ||
                  widget.initialSlotId == slot.id) &&
              statuses[slot.id]?.reasonCannotSchedule(_on) == null &&
              statuses.containsKey(slot.id)) {
            _selected.add(slot.id);
          }
        }
        _firstLoad = false;
      }
      _selected.removeWhere(
        (id) =>
            !statuses.containsKey(id) ||
            statuses[id]!.reasonCannotSchedule(_on) != null,
      );
    });
  }

  String _timeLabel(DateTime time) {
    final local = time.toLocal();
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final day = DateUtils.isSameDay(local, today)
        ? 'Today'
        : DateUtils.isSameDay(local, tomorrow)
        ? 'Tomorrow'
        : '${local.day}/${local.month}';
    return '$day, ${TimeOfDay.fromDateTime(local).format(context)}';
  }

  String _remainingLabel(LightTimer timer) {
    final seconds = timer.endsAt.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 'Due now. Refresh to confirm it finished.';
    final minutes = (seconds / 60).ceil();
    return 'About $minutes ${minutes == 1 ? 'minute' : 'minutes'} remaining';
  }

  DateTime? get _target {
    if (_atTime) return _scheduledAt;
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null || minutes < 1 || minutes > 1440) return null;
    return DateTime.now().add(Duration(minutes: minutes));
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduledAt ?? DateTime.now().add(const Duration(minutes: 30)),
      ),
    );
    if (!mounted || result == null) return;
    setState(
      () => _scheduledAt = nextTimerTime(
        DateTime.now(),
        result.hour,
        result.minute,
      ),
    );
  }

  Future<void> _save({String? cancelSlot}) async {
    FocusScope.of(context).unfocus();
    final target = _target;
    if (cancelSlot == null && (target == null || _selected.isEmpty)) return;
    ++_loadVersion;
    setState(() {
      _saving = true;
      _loading = false;
      _report = null;
    });
    final controller = ref.read(appControllerProvider.notifier);
    final report = cancelSlot == null
        ? await controller.scheduleTimers(Set.of(_selected), target!, on: _on)
        : await controller.cancelLightTimer(cancelSlot);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _report = report;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(report.message),
        duration: Duration(seconds: report.hasFailures ? 8 : 3),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    ref.listen(appControllerProvider, (previous, next) {
      if (previous?.settings.demo != next.settings.demo ||
          previous?.config != next.config) {
        ++_loadVersion;
        _statuses = {};
        _errors = {};
        _report = null;
        _loading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_saving && _foreground) _load();
        });
      }
      if (!_saving &&
          _foreground &&
          previous?.connected == false &&
          next.connected) {
        _load();
      }
    });
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final blocked =
        _saving || _loading || state.busy.isNotEmpty || !_foreground;
    final target = _target;
    final validTime =
        target != null &&
        target.difference(DateTime.now()).inSeconds >= 1 &&
        target.difference(DateTime.now()).inSeconds <= 86400;
    final active = state.slots
        .where((slot) => _statuses[slot.id]?.active != null)
        .toList();

    final editor = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set a timer', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('One action, at just the right time.'),
          const SizedBox(height: 24),
          Text('ACTION', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Turn off'),
                  icon: Icon(Icons.bedtime_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Turn on'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
              ],
              selected: {_on},
              onSelectionChanged: blocked
                  ? null
                  : (values) => setState(() {
                      _on = values.single;
                      _selected.removeWhere(
                        (id) =>
                            _statuses[id]?.reasonCannotSchedule(_on) != null,
                      );
                    }),
            ),
          ),
          const SizedBox(height: 24),
          Text('WHEN', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('After a delay')),
                ButtonSegment(value: true, label: Text('At a time')),
              ],
              selected: {_atTime},
              onSelectionChanged: blocked
                  ? null
                  : (values) => setState(() => _atTime = values.single),
            ),
          ),
          const SizedBox(height: 16),
          if (_atTime) ...[
            OutlinedButton.icon(
              key: const ValueKey('choose-timer-time'),
              onPressed: blocked ? null : _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                _scheduledAt == null
                    ? 'Choose time'
                    : _timeLabel(_scheduledAt!),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Runs once, within the next 24 hours. Times use this device’s time zone.',
            ),
            if (_scheduledAt != null && !validTime)
              Text(
                'That time has passed or is beyond 24 hours. Choose another time.',
                style: TextStyle(color: scheme.error),
              ),
          ] else ...[
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
                    selected: _minutes.text == '$minutes',
                    onSelected: blocked
                        ? null
                        : (_) => _minutes.text = '$minutes',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('timer-minutes'),
              controller: _minutes,
              enabled: !blocked,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Minutes',
                suffixText: 'min',
                helperText: '1–1,440 minutes (up to 24 hours)',
                errorText: target == null ? 'Enter 1 to 1,440 minutes.' : null,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('LIGHTS', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          for (final slot in state.slots)
            Builder(
              builder: (context) {
                final status = _statuses[slot.id];
                final reason =
                    _errors[slot.id] ??
                    status?.reasonCannotSchedule(_on) ??
                    (status == null ? 'Checking this light…' : null);
                return CheckboxListTile(
                  key: ValueKey('timer-light-${slot.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(slot.name),
                  subtitle: Text(
                    reason ??
                        (status!.togglesPower
                            ? 'Power changes cancel this light’s timer.'
                            : 'Ready for a timer.'),
                  ),
                  value: _selected.contains(slot.id),
                  onChanged: blocked || reason != null
                      ? null
                      : (selected) => setState(() {
                          selected == true
                              ? _selected.add(slot.id)
                              : _selected.remove(slot.id);
                        }),
                );
              },
            ),
          const SizedBox(height: 16),
          if (validTime && _selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${_selected.length} ${_selected.length == 1 ? 'light' : 'lights'} · Turn ${_on ? 'on' : 'off'} · ${_timeLabel(target)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('set-timer'),
              onPressed: blocked || !validTime || _selected.isEmpty
                  ? null
                  : () => _save(),
              icon: const Icon(Icons.timer_outlined),
              label: Text(_saving ? 'Saving…' : 'Set timer'),
            ),
          ),
        ],
      ),
    );
    final running = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.nights_stay_outlined, color: scheme.primary, size: 30),
              const SizedBox(height: 16),
              Text('Set it. Close the app.', style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                state.settings.demo
                    ? 'Preview mode: timers are simulated while this demo is open.'
                    : 'Timers are saved on the lights, so your phone or computer can sleep.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Keep the wall switches on. Changing Wipro’s power in an app cancels its countdown. Power loss may clear timers.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On the lights', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'One timer per light. Check or cancel it from any of your connected devices.',
              ),
              const SizedBox(height: 16),
              if (active.isEmpty)
                Text(
                  _loading
                      ? 'Checking timers…'
                      : _errors.isNotEmpty ||
                            _statuses.values.any((s) => !s.supported)
                      ? 'Some lights could not be checked. Refresh to see their timers.'
                      : 'No active timers on checked lights.',
                ),
              for (final slot in active) ...[
                const Divider(height: 24),
                Text(slot.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Turn ${_statuses[slot.id]!.active!.on ? 'on' : 'off'} · ${_timeLabel(_statuses[slot.id]!.active!.endsAt)}',
                ),
                Text(
                  _remainingLabel(_statuses[slot.id]!.active!),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: ValueKey('cancel-timer-${slot.id}'),
                  onPressed: blocked ? null : () => _save(cancelSlot: slot.id),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel timer'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: blocked ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh timers'),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Timers')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeading(
                'A little later.',
                'Schedule your lights to turn on or off, even with SmartLight closed.',
              ),
              if (_report case final report?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (report.succeeded.isNotEmpty)
                          Text(
                            '${report.succeeded.join(', ')}: ${report.successVerb}.',
                            style: TextStyle(color: scheme.primary),
                          ),
                        for (final failure in report.failed.entries)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${failure.key}: ${failure.value}',
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 820
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: editor),
                          const SizedBox(width: 24),
                          Expanded(flex: 5, child: running),
                        ],
                      )
                    : Column(
                        children: [editor, const SizedBox(height: 20), running],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
