import 'dart:async';

import '../models/device_slot.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../repositories/lights_repository.dart';
import 'ha_exception.dart';
import 'home_assistant_websocket.dart';

class MockHomeAssistant implements LightsRepository {
  MockHomeAssistant({this.latency = const Duration(milliseconds: 100)}) {
    for (final slot in DeviceSlot.demo) {
      final strip = slot.id == 'strip';
      _lights[slot.entityId!] = LightEntity.fromJson({
        'entity_id': slot.entityId,
        'state': 'on',
        'attributes': {
          'friendly_name': slot.name,
          'brightness': strip ? 128 : 200,
          'rgb_color': strip ? [80, 20, 255] : [255, 220, 180],
          'color_temp_kelvin': 4000,
          'min_color_temp_kelvin': 2000,
          'max_color_temp_kelvin': 6500,
          'color_mode': strip ? 'rgb' : 'color_temp',
          'supported_color_modes': ['rgb', 'color_temp'],
        },
      });
    }
  }
  final Duration latency;
  final _lights = <String, LightEntity>{};
  final _updates = StreamController<LightEntity>.broadcast();
  final _statuses = StreamController<RealtimeStatus>.broadcast();
  bool offline = false;
  bool _disposed = false;
  final Set<String> failCommands = {};
  @override
  Stream<LightEntity> get updates => _updates.stream;
  @override
  Stream<RealtimeStatus> get statuses => _statuses.stream;
  Future<void> _check() async {
    await Future<void>.delayed(latency);
    if (offline) {
      throw const HaException(
        HaError.unreachable,
        'Home Assistant offline (demo).',
      );
    }
  }

  @override
  Future<void> testConnection() => _check();
  @override
  Future<List<LightEntity>> getLights() async {
    await _check();
    return _lights.values.toList();
  }

  @override
  Future<LightEntity> getLight(String id) async {
    await _check();
    return _lights[id]!;
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) async {
    await _check();
    if (failCommands.contains(light.entityId)) {
      throw const HaException(
        HaError.server,
        'Demo device rejected the command.',
      );
    }
    final current = _lights[light.entityId]!;
    if (!current.available) {
      throw const HaException(HaError.unavailable, 'Device unavailable.');
    }
    final data = command.toServiceData(current)..remove('entity_id');
    final attrs = {...current.rawAttributes, ...data};
    if (data.containsKey('rgb_color')) attrs['color_mode'] = 'rgb';
    if (data.containsKey('color_temp_kelvin')) {
      attrs['color_mode'] = 'color_temp';
    }
    _emit(
      LightEntity(
        entityId: current.entityId,
        friendlyName: current.friendlyName,
        state: command.service == 'turn_off' ? 'off' : 'on',
        attributes: attrs,
      ),
    );
  }

  void _emit(LightEntity light) {
    _lights[light.entityId] = light;
    if (!_disposed) _updates.add(light);
  }

  void setAvailable(String id, bool available) {
    final light = _lights[id]!;
    _emit(
      LightEntity(
        entityId: id,
        friendlyName: light.friendlyName,
        state: available ? 'off' : 'unavailable',
        attributes: light.rawAttributes,
      ),
    );
  }

  void setOffline(bool value) {
    offline = value;
    if (!_disposed) {
      _statuses.add(
        value ? RealtimeStatus.reconnecting : RealtimeStatus.connected,
      );
    }
  }

  @override
  void start() {
    if (!_disposed) _statuses.add(RealtimeStatus.connected);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates.close());
    unawaited(_statuses.close());
  }
}
