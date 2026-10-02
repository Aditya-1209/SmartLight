import '../../models/light_timer.dart';

/// Optional capability. All operations talk directly to the device.
abstract interface class DeviceTimerClient {
  Future<LightTimerStatus> readTimer();
  Future<LightTimerStatus> setTimer(DateTime endsAt, {required bool on});
  Future<LightTimerStatus> cancelTimer();
}
