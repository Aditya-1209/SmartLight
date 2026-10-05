import '../../models/connection_config.dart';
import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../models/light_timer.dart';
import '../device_exception.dart';
import 'device_client.dart';
import 'device_timer_client.dart';
import 'resolved_connection.dart';
import 'tuya_client.dart';
import 'tuya_lan_discovery.dart';

/// Uses the paired device ID to find an address, then verifies an encrypted
/// status read with the existing per-device key before saving or writing.
class AutoTuyaClient implements DeviceClient, DeviceTimerClient {
  AutoTuyaClient(
    this.config, {
    TuyaDiscover? discover,
    DeviceClient Function(DeviceConnection)? factory,
    this.onResolved,
    DateTime Function()? clock,
  }) : _discover = discover ?? TuyaLanDiscovery.scan,
       _factory = factory ?? TuyaClient.new,
       _clock = clock ?? DateTime.now {
    _client = _factory(config);
  }

  DeviceConnection config;
  final TuyaDiscover _discover;
  final DeviceClient Function(DeviceConnection) _factory;
  final void Function(ResolvedConnection)? onResolved;
  final DateTime Function() _clock;
  final _queue = DeviceQueue();
  late DeviceClient _client;
  DateTime? _lastDiscovery;
  bool _disposed = false;

  void _checkOpen() {
    if (_disposed) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Connection closed.',
      );
    }
  }

  LightEntity _verified(LightEntity light, DeviceConnection candidate) {
    _checkOpen();
    if (!light.available) {
      throw const DeviceException(
        DeviceError.unavailable,
        'The tube did not report a usable light state.',
      );
    }
    if (candidate.host != config.host) {
      final previous = config;
      config = candidate;
      onResolved?.call(ResolvedConnection(previous, candidate));
    }
    return LightEntity(
      entityId: light.entityId,
      friendlyName: light.friendlyName,
      state: light.state,
      attributes: {...light.rawAttributes, 'connection_host': config.host},
    );
  }

  Future<LightEntity> _read() async {
    _checkOpen();
    try {
      return _verified(await _client.read(), config);
    } on DeviceException catch (original) {
      _checkOpen();
      // A changed address may be offline, or now belong to a different device.
      // Only read failures reach here; uncertain writes are never replayed.
      if (_lastDiscovery != null &&
          _clock().difference(_lastDiscovery!) < const Duration(seconds: 30)) {
        rethrow;
      }
      _lastDiscovery = _clock();
      List<TuyaDiscoveredLight> found;
      try {
        found = await _discover();
      } catch (_) {
        _checkOpen();
        throw original;
      }
      _checkOpen();
      final hosts = found
          .where(
            (d) =>
                d.deviceId == config.deviceId &&
                DeviceConnection.isLocalAddress(d.host),
          )
          .map((d) => d.host)
          .toSet();
      if (hosts.length != 1 || hosts.single == config.host) {
        if (original.kind == DeviceError.unreachable ||
            original.kind == DeviceError.timeout) {
          throw const DeviceException(
            DeviceError.unreachable,
            'Tube not found yet. Keep its wall switch on, join the same Wi-Fi and try Refresh after it reconnects. You do not need to factory reset it for an IP change.',
          );
        }
        rethrow;
      }
      final candidate = config.withAddress(host: hosts.single);
      final next = _factory(candidate);
      try {
        final light = _verified(await next.read(), candidate);
        _client.dispose();
        _client = next;
        return light;
      } catch (_) {
        next.dispose();
        rethrow;
      }
    }
  }

  @override
  Future<LightEntity> read() => _queue.run(_read);

  @override
  Future<void> command(LightEntity light, LightCommand command) =>
      _queue.run(() async {
        final current = await _read();
        _checkOpen();
        await _client.command(current, command);
      });

  Future<LightTimerStatus> _withTimer(
    Future<LightTimerStatus> Function(DeviceTimerClient) action,
  ) => _queue.run(() async {
    await _read();
    _checkOpen();
    final client = _client;
    if (client is! DeviceTimerClient) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Built-in timers are not supported.',
      );
    }
    return action(client as DeviceTimerClient);
  });

  @override
  Future<LightTimerStatus> readTimer() => _withTimer((c) => c.readTimer());
  @override
  Future<LightTimerStatus> setTimer(DateTime endsAt, {required bool on}) =>
      _withTimer((c) => c.setTimer(endsAt, on: on));
  @override
  Future<LightTimerStatus> cancelTimer() => _withTimer((c) => c.cancelTimer());
  @override
  void dispose() {
    _disposed = true;
    _client.dispose();
  }
}
