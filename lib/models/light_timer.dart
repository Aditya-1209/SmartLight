import '../services/device_exception.dart';

/// A countdown stored on the light, never an app/background alarm.
class LightTimer {
  const LightTimer({required this.id, required this.endsAt, required this.on});
  final String id;
  final DateTime endsAt;
  final bool on;
}

class LightTimerStatus {
  const LightTimerStatus({
    required this.isOn,
    this.active,
    this.togglesPower = false,
    this.unsupportedReason,
  });
  final bool isOn;
  final LightTimer? active;
  final bool togglesPower;
  final String? unsupportedReason;
  bool get supported => unsupportedReason == null;

  String? reasonCannotSchedule(bool on) =>
      unsupportedReason ??
      (active != null
          ? 'Cancel the existing timer before setting another.'
          : togglesPower && on == isOn
          ? 'Turn this light ${on ? 'off' : 'on'} first to schedule it ${on ? 'on' : 'off'}.'
          : null);
}

/// Evaluated immediately before sending, so connection delays do not extend a
/// chosen clock time. The request must still be in the next 24 hours.
int countdownSeconds(DateTime endsAt, {DateTime? now}) {
  final milliseconds = endsAt.difference(now ?? DateTime.now()).inMilliseconds;
  if (milliseconds < 1000 ||
      milliseconds > const Duration(days: 1).inMilliseconds) {
    throw const DeviceException(
      DeviceError.unavailable,
      'Choose a time at least a few seconds away, within the next 24 hours.',
    );
  }
  return milliseconds ~/ 1000;
}

DateTime nextTimerTime(DateTime now, int hour, int minute) {
  var target = DateTime(now.year, now.month, now.day, hour, minute);
  if (!target.isAfter(now)) {
    target = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  return target;
}

void requireTimerAvailable(LightTimerStatus status, bool on) {
  final reason = status.reasonCannotSchedule(on);
  if (reason != null) throw DeviceException(DeviceError.unavailable, reason);
}

const timerUnconfirmed = DeviceException(
  DeviceError.unavailable,
  'The timer request was sent, but could not be confirmed. Refresh timers before trying again.',
);
