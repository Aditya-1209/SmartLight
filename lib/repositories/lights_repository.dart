import 'dart:async';

import '../models/connection_config.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../services/connection_status.dart';
import '../services/device_exception.dart';
import '../services/local/device_client.dart';
import '../services/local/tapo_client.dart';
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

class LocalLightsRepository implements LightsRepository {
  LocalLightsRepository(this.config, {DeviceClientFactory? factory}) {
    for (final device in config.devices) {
      _clients[device.entityId] =
          factory?.call(device) ??
          (device.brand == DeviceBrand.tapo
              ? TapoClient(device)
              : TuyaClient(device));
    }
  }
  final ConnectionConfig config;
  final _clients = <String, DeviceClient>{};
  final _statuses = StreamController<ConnectionStatus>.broadcast();
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
  @override
  void start() {}
  @override
  void dispose() {
    _disposed = true;
    for (final client in _clients.values) {
      client.dispose();
    }
    unawaited(_statuses.close());
  }
}
