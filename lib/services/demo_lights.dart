import 'dart:async';

import '../models/device_slot.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../models/light_timer.dart';
import '../repositories/lights_repository.dart';
import 'device_exception.dart';
import 'connection_status.dart';

class DemoLights implements LightsRepository, LightTimersRepository {
  DemoLights({this.latency = const Duration(milliseconds: 100)}) {
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
  final _timers = <String, LightTimer>{};
  final _updates = StreamController<LightEntity>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  bool offline = false;
  bool _disposed = false;
  final Set<String> failCommands = {};
  @override
  Stream<LightEntity> get updates => _updates.stream;
  @override
  Stream<ConnectionStatus> get statuses => _statuses.stream;
  Future<void> _check() async {
    await Future<void>.delayed(latency);
    if (offline) {
      throw const DeviceException(
        DeviceError.unreachable,
        'Room Wi-Fi offline (demo).',
      );
    }
    for (final entry in _timers.entries.toList()) {
      if (entry.value.endsAt.isAfter(DateTime.now())) continue;
      final light = _lights[entry.key]!;
      _emit(
        LightEntity(
          entityId: light.entityId,
          friendlyName: light.friendlyName,
          state: entry.value.on ? 'on' : 'off',
          attributes: light.rawAttributes,
        ),
      );
      _timers.remove(entry.key);
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
      throw const DeviceException(
        DeviceError.server,
        'Demo device rejected the command.',
      );
    }
    final current = _lights[light.entityId]!;
    if (!current.available) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Device unavailable.',
      );
    }
    if (!light.entityId.contains('tapo') &&
        current.isOn != (command.service != 'turn_off')) {
      _timers.remove(light.entityId);
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
        value ? ConnectionStatus.reconnecting : ConnectionStatus.connected,
      );
    }
  }

  @override
  Future<LightTimerStatus> readTimer(String id) async {
    await _check();
    final light = _lights[id];
    if (light == null || !light.available) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Light unavailable.',
      );
    }
    return LightTimerStatus(
      isOn: light.isOn,
      active: _timers[id],
      togglesPower: !id.contains('tapo'),
    );
  }

  @override
  Future<LightTimerStatus> setTimer(
    String id,
    DateTime endsAt, {
    required bool on,
  }) async {
    final current = await readTimer(id);
    requireTimerAvailable(current, on);
    countdownSeconds(endsAt);
    if (failCommands.contains(id)) {
      throw const DeviceException(DeviceError.server, 'Demo timer rejected.');
    }
    _timers[id] = LightTimer(id: 'demo', endsAt: endsAt, on: on);
    return readTimer(id);
  }

  @override
  Future<LightTimerStatus> cancelTimer(String id) async {
    await readTimer(id);
    if (failCommands.contains(id)) {
      throw const DeviceException(DeviceError.server, 'Demo timer rejected.');
    }
    _timers.remove(id);
    return readTimer(id);
  }

  @override
  void start() {
    if (!_disposed) _statuses.add(ConnectionStatus.connected);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates.close());
    unawaited(_statuses.close());
  }
}
