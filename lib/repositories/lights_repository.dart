import 'dart:async';

import '../models/connection_config.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../models/light_timer.dart';
import '../services/connection_status.dart';
import '../services/device_exception.dart';
import '../services/local/device_client.dart';
import '../services/local/device_timer_client.dart';
import '../services/local/auto_tapo_client.dart';
import '../services/local/tapo_discovery.dart';
import '../services/local/tuya_client.dart';

abstract interface class LightsRepository {
  Stream<LightEntity> get updates;
  Stream<ConnectionStatus> get statuses;
  Future<void> testConnection();
  Future<List<LightEntity>> getLights();
  Future<LightEntity> getLight(String id);
  Future<void> command(LightEntity light, LightCommand command);
  void start();
  void dispose();
}

typedef DeviceClientFactory = DeviceClient Function(DeviceConnection config);

abstract interface class LightTimersRepository {
  Future<LightTimerStatus> readTimer(String id);
  Future<LightTimerStatus> setTimer(
    String id,
    DateTime endsAt, {
    required bool on,
  });
  Future<LightTimerStatus> cancelTimer(String id);
}

class LocalLightsRepository implements LightsRepository, LightTimersRepository {
  LocalLightsRepository(
    this.config, {
    DeviceClientFactory? factory,
    DeviceClientFactory? tapoClientFactory,
    TapoDiscover? tapoDiscover,
  }) {
    for (final device in config.devices) {
      _clients[device.entityId] =
          factory?.call(device) ??
          (device.brand == DeviceBrand.tapo
              ? AutoTapoClient(
                  device,
                  factory: tapoClientFactory,
                  discover: tapoDiscover,
                  onResolved: (event) {
                    if (!_disposed) _connections.add(event);
                  },
                )
              : TuyaClient(device));
    }
  }
  final ConnectionConfig config;
  final _clients = <String, DeviceClient>{};
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  final _connections = StreamController<ResolvedConnection>.broadcast();
  Stream<ResolvedConnection> get connectionUpdates => _connections.stream;
  bool _disposed = false;
  @override
  Stream<LightEntity> get updates => const Stream.empty();
  @override
  Stream<ConnectionStatus> get statuses => _statuses.stream;
  @override
  Future<void> testConnection() async {
    for (final client in _clients.values) {
      await client.read();
    }
  }

  @override
  Future<List<LightEntity>> getLights() async {
    final lights = await Future.wait(
      config.devices.map((device) async {
        try {
          return await _clients[device.entityId]!.read();
        } catch (error) {
          return LightEntity(
            entityId: device.entityId,
            friendlyName: device.name,
            state: 'unavailable',
            attributes: {'connection_error': userMessage(error)},
          );
        }
      }),
    );
    if (!_disposed) {
      _statuses.add(
        lights.every((light) => light.available)
            ? ConnectionStatus.connected
            : ConnectionStatus.reconnecting,
      );
    }
    return lights;
  }

  @override
  Future<LightEntity> getLight(String id) => _client(id).read();
  DeviceClient _client(String id) =>
      _clients[id] ??
      (throw const DeviceException(
        DeviceError.unavailable,
        'Set up this light first.',
      ));
  @override
  Future<void> command(LightEntity light, LightCommand command) =>
      _client(light.entityId).command(light, command);

  DeviceTimerClient _timerClient(String id) {
    final client = _client(id);
    if (client is DeviceTimerClient) return client as DeviceTimerClient;
    throw const DeviceException(
      DeviceError.unavailable,
      'This light does not support built-in timers.',
    );
  }

  @override
  Future<LightTimerStatus> readTimer(String id) => _timerClient(id).readTimer();
  @override
  Future<LightTimerStatus> setTimer(
    String id,
    DateTime endsAt, {
    required bool on,
  }) => _timerClient(id).setTimer(endsAt, on: on);
  @override
  Future<LightTimerStatus> cancelTimer(String id) =>
      _timerClient(id).cancelTimer();
  @override
  void start() {}
  @override
  void dispose() {
    _disposed = true;
    for (final client in _clients.values) {
      client.dispose();
    }
    unawaited(_statuses.close());
    unawaited(_connections.close());
  }
}
