import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_config.dart';
import '../models/device_slot.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../models/scene.dart';
import '../repositories/lights_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/device_exception.dart';
import '../services/connection_status.dart';
import '../services/demo_lights.dart';
import '../services/secure_storage_service.dart';
import '../services/local/device_client.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureStorageService(),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsRepository(),
);
typedef BackendFactory = LightsRepository Function(
  ConnectionConfig? config,
  bool demo,
);
final backendFactoryProvider = Provider<BackendFactory>(
  (ref) =>
      (config, demo) => demo ? DemoLights() : LocalLightsRepository(config!),
);
final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.settings = const AppSettings(),
    this.config,
    this.lights = const {},
    this.busy = const {},
    this.loading = false,
    this.connected = false,
    this.realtime = ConnectionStatus.disconnected,
    this.lastRefresh,
    this.error,
  });
  final AppSettings settings;
  final ConnectionConfig? config;
  final Map<String, LightEntity> lights;
  final Set<String> busy;
  final bool loading;
  final bool connected;
  final ConnectionStatus realtime;
  final DateTime? lastRefresh;
  final String? error;
  bool get configured => settings.demo || (config?.devices.isNotEmpty ?? false);
  List<DeviceSlot> get slots => settings.demo
      ? DeviceSlot.demo
      : DeviceSlot.defaults.map((slot) {
          final device = config?.devices
              .where((d) => d.slotId == slot.id)
              .firstOrNull;
          return DeviceSlot(
            id: slot.id,
            name: device?.name ?? slot.name,
            entityId: device?.entityId,
          );
        }).toList();
  LightEntity? lightFor(DeviceSlot slot) => lights[slot.entityId];
  AppState copyWith({
    AppSettings? settings,
    ConnectionConfig? config,
    Map<String, LightEntity>? lights,
    Set<String>? busy,
    bool? loading,
    bool? connected,
    ConnectionStatus? realtime,
    DateTime? lastRefresh,
    String? error,
    bool clearError = false,
  }) => AppState(
    settings: settings ?? this.settings,
    config: config ?? this.config,
    lights: lights ?? this.lights,
    busy: busy ?? this.busy,
    loading: loading ?? this.loading,
    connected: connected ?? this.connected,
    realtime: realtime ?? this.realtime,
    lastRefresh: lastRefresh ?? this.lastRefresh,
    error: clearError ? null : error ?? this.error,
  );
}

class ActionReport {
  ActionReport({
    required this.succeeded,
    required this.failed,
    required this.skipped,
  });
  final List<String> succeeded;
  final Map<String, String> failed;
  final List<String> skipped;
  bool get hasFailures => failed.isNotEmpty;
  String get message => failed.isNotEmpty
      ? failed.entries.map((e) => '${e.key}: ${e.value}').join(' • ')
      : succeeded.isEmpty
      ? 'No compatible connected lights.'
      : '${succeeded.length} ${succeeded.length == 1 ? 'light' : 'lights'} updated${skipped.isEmpty ? '.' : '; ${skipped.length} unsupported skipped.'}';
}

class AppController extends Notifier<AppState> {
  LightsRepository? _backend;
  StreamSubscription<LightEntity>? _updates;
  StreamSubscription<ConnectionStatus>? _statuses;
  Timer? _fallbackRefresh;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  Future<void>? _initialization;
  final Map<String, int> _revisions = {};
  final _configurationQueue = DeviceQueue();
  @override
  AppState build() {
    ref.onDispose(() {
      _disposed = true;
      _detach();
    });
    return const AppState();
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    state = state.copyWith(loading: true);
    try {
      final settings = await ref.read(settingsStoreProvider).read();
      final config = await ref.read(credentialStoreProvider).read();
      if (_disposed) return;
      state = AppState(settings: settings, config: config);
      if (state.configured) await _attach();
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          loading: false,
          error: 'Could not read saved settings or secure credentials. Check your system keychain and try again.',
        );
      }
    }
  }

  void _detach() {
    ++_generation;
    _fallbackRefresh?.cancel();
    unawaited(_updates?.cancel());
    unawaited(_statuses?.cancel());
    _backend?.dispose();
    _backend = null;
    _revisions.clear();
  }

  Future<void> _attach() async {
    _detach();
    if (!state.configured || !_foreground) {
      state = state.copyWith(
        lights: {},
        connected: false,
        realtime: ConnectionStatus.disconnected,
      );
      return;
    }
    final generation = _generation;
    final backend = ref.read(backendFactoryProvider)(
      state.config,
      state.settings.demo,
    );
    _backend = backend;
    state = AppState(
      settings: state.settings,
      config: state.config,
      loading: true,
    );
    _updates = backend.updates.listen((light) {
      if (_disposed || generation != _generation) return;
      _revisions[light.entityId] = (_revisions[light.entityId] ?? 0) + 1;
      state = state.copyWith(lights: {...state.lights, light.entityId: light});
    });
    _statuses = backend.statuses.listen((status) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        realtime: status,
        error: status == ConnectionStatus.unauthorized
            ? 'A light rejected its credentials. Check Settings.'
            : null,
      );
    });
    backend.start();
    _fallbackRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.busy.isEmpty) unawaited(refresh());
    });
    await refresh(force: true);
  }

  Future<void> refresh({bool force = false}) async {
    final backend = _backend;
    if (backend == null || (state.loading && !force)) return;
    final generation = _generation;
    final versions = Map<String, int>.of(_revisions);
    state = state.copyWith(loading: true);
    try {
      final lights = await backend.getLights();
      if (_disposed || generation != _generation) return;
      final merged = {for (final light in lights) light.entityId: light};
      // A newer command/event wins over a poll already in flight.
      for (final entry in state.lights.entries) {
        if ((_revisions[entry.key] ?? 0) != (versions[entry.key] ?? 0)) {
          merged[entry.key] = entry.value;
        }
      }
      state = state.copyWith(
        lights: merged,
        loading: false,
        connected: merged.values.any((light) => light.available),
        lastRefresh: merged.values.any((light) => light.available)
            ? DateTime.now()
            : null,
        error: merged.values.any((light) => light.available)
            ? null
            : 'No lights reachable. Check your Wi-Fi and device settings.',
        clearError: merged.values.any((light) => light.available),
      );
    } catch (error) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          loading: false,
          connected: false,
          error: userMessage(error),
        );
      }
    }
  }

  Future<LightEntity> inspectDevice(DeviceConnection device) async {
    final backend = ref.read(backendFactoryProvider)(
      ConnectionConfig([device]),
      false,
    );
    try {
      return await backend.getLight(device.entityId);
    } finally {
      backend.dispose();
    }
  }

  Future<void> saveDevice(DeviceConnection device) =>
      _configurationQueue.run(() => _saveDevice(device));
  Future<void> _saveDevice(DeviceConnection device) async {
    final devices = [
      ...?state.config?.devices.where((d) => d.slotId != device.slotId),
      device,
    ];
    final config = ConnectionConfig(devices);
    final light = await inspectDevice(device);
    if (!light.available) {
      throw const DeviceException(
        DeviceError.unavailable,
        'The light did not report a usable state.',
      );
    }
    await _saveConfig(config);
  }

  Future<void> removeDevice(String slotId) =>
      _configurationQueue.run(() => _removeDevice(slotId));
  Future<void> _removeDevice(String slotId) async {
    final config = ConnectionConfig(
      state.config?.devices.where((d) => d.slotId != slotId).toList() ?? [],
    );
    await _saveConfig(config);
  }

  Future<void> _saveConfig(ConnectionConfig config) async {
    final settings = state.settings.copyWith(demo: false);
    try {
      await ref.read(credentialStoreProvider).write(config);
      await ref.read(settingsStoreProvider).write(settings);
    } catch (_) {
      throw const DeviceException(
        DeviceError.storage,
        'Could not save securely. Check your system keychain and storage permissions.',
      );
    }
    if (_disposed) return;
    state = state.copyWith(
      config: config,
      settings: settings,
      clearError: true,
    );
    await _attach();
  }

  Future<void> setForeground(bool foreground) async {
    if (_disposed) return;
    _foreground = foreground;
    if (foreground) {
      if (_backend == null && state.configured) await _attach();
    } else {
      _detach();
      state = state.copyWith(
        loading: false,
        connected: false,
        busy: {},
        realtime: ConnectionStatus.disconnected,
      );
    }
  }

  Future<void> setDemo(bool value) async {
    final settings = state.settings.copyWith(demo: value);
    await ref.read(settingsStoreProvider).write(settings);
    if (_disposed) return;
    state = AppState(config: state.config, settings: settings);
    await _attach();
  }

  Future<void> setTheme(ThemeMode theme) async {
    final settings = state.settings.copyWith(theme: theme);
    await ref.read(settingsStoreProvider).write(settings);
    if (!_disposed) state = state.copyWith(settings: settings);
  }

  Future<ActionReport> control(DeviceSlot slot, LightCommand command) =>
      _run({slot.id: command});
  Future<ActionReport> controlAll(LightCommand command) =>
      _run({for (final s in state.slots) s.id: command}, skipUnsupported: true);
  Future<ActionReport> applyScene(LightScene scene) => _run(scene.commands);
  Future<ActionReport> _run(
    Map<String, LightCommand> commands, {
    bool skipUnsupported = false,
  }) async {
    final succeeded = <String>[];
    final failed = <String, String>{};
    final skipped = <String>[];
    final backend = _backend;
    final generation = _generation;
    final targets = state.slots
        .where((s) => commands.containsKey(s.id))
        .toList();
    if (state.busy.isNotEmpty) {
      return ActionReport(
        succeeded: [],
        failed: {'Room': 'Wait for the current action to finish.'},
        skipped: [],
      );
    }
    state = state.copyWith(busy: targets.map((s) => s.id).toSet());
    await Future.wait(
      targets.map((slot) async {
        final light = state.lightFor(slot);
        final command = commands[slot.id]!;
        if (backend == null || light == null) {
          failed[slot.name] = 'Not set up.';
          return;
        }
        if (!light.available) {
          failed[slot.name] = 'Unavailable.';
          return;
        }
        if (skipUnsupported && !command.compatibleWith(light)) {
          skipped.add(slot.name);
          return;
        }
        try {
          await backend.command(light, command);
          _revisions[light.entityId] = (_revisions[light.entityId] ?? 0) + 1;
          final revision = _revisions[light.entityId] ?? 0;
          final updated = await backend.getLight(light.entityId);
          if (!_disposed &&
              generation == _generation &&
              revision == (_revisions[light.entityId] ?? 0)) {
            state = state.copyWith(
              lights: {...state.lights, updated.entityId: updated},
            );
          }
          succeeded.add(slot.name);
        } catch (error) {
          failed[slot.name] = userMessage(error);
        }
      }),
    );
    if (!_disposed && generation == _generation) {
      state = state.copyWith(busy: {});
    }
    return ActionReport(succeeded: succeeded, failed: failed, skipped: skipped);
  }

  void setDemoAvailability(DeviceSlot slot, bool available) {
    final backend = _backend;
    if (backend is DemoLights && slot.entityId != null) {
      backend.setAvailable(slot.entityId!, available);
    }
  }

  Future<void> setDemoOffline(bool value) async {
    final backend = _backend;
    if (backend is DemoLights) {
      backend.setOffline(value);
      await refresh();
    }
  }
}
