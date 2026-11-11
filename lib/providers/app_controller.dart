import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_config.dart';
import '../models/device_slot.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../models/light_timer.dart';
import '../models/scene.dart';
import '../repositories/lights_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/device_exception.dart';
import '../services/connection_status.dart';
import '../services/demo_lights.dart';
import '../services/secure_storage_service.dart';
import '../services/local/device_client.dart';
import '../services/local/auto_tapo_client.dart';
import '../services/local/tuya_protocol.dart';

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
final timerSetupGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
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
    this.timerWarning,
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
  final String? timerWarning;
  bool get configured => settings.demo || (config?.devices.isNotEmpty ?? false);
  List<DeviceSlot> get slots =>
      settings.demo ? DeviceSlot.demo : configuredSlots;
  List<DeviceSlot> get configuredSlots => settings.slots.map((slot) {
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
  List<LightScene> get scenes => [
    ...settings.customScenes,
    ...LightScene.defaults,
  ];
  List<LightScene> get roomScenes {
    final ids = settings.roomSceneIds;
    if (ids == null) return scenes.take(4).toList();
    final byId = {for (final scene in scenes) scene.id: scene};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

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
    String? timerWarning,
    bool clearTimerWarning = false,
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
    timerWarning: clearTimerWarning ? null : timerWarning ?? this.timerWarning,
  );
}

class ActionReport {
  ActionReport({
    required this.succeeded,
    required this.failed,
    required this.skipped,
    this.successVerb = 'updated',
  });
  final List<String> succeeded;
  final Map<String, String> failed;
  final List<String> skipped;
  final String successVerb;
  bool get hasFailures => failed.isNotEmpty;
  String get message => failed.isNotEmpty
      ? failed.entries.map((e) => '${e.key}: ${e.value}').join(' • ')
      : succeeded.isEmpty
      ? 'No compatible connected lights.'
      : '${succeeded.length} ${succeeded.length == 1 ? 'light' : 'lights'} $successVerb${skipped.isEmpty ? '.' : '; ${skipped.length} unsupported skipped.'}';
}

class AppController extends Notifier<AppState> {
  LightsRepository? _backend;
  StreamSubscription<LightEntity>? _updates;
  StreamSubscription<ConnectionStatus>? _statuses;
  StreamSubscription<ResolvedConnection>? _connections;
  Timer? _fallbackRefresh;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  int _pendingTimerSetups = 0;
  Timer? _backgroundDisconnect;
  Future<void>? _initialization;
  bool _storageReady = false;
  final Map<String, int> _revisions = {};
  final _pendingAddresses = <String, ResolvedConnection>{};
  final _configurationQueue = DeviceQueue();
  @override
  AppState build() {
    ref.onDispose(() {
      _disposed = true;
      _detach();
    });
    return const AppState();
  }

  Future<void> initialize() {
    if (_storageReady) return Future.value();
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    state = state.copyWith(loading: true);
    try {
      final settings = await ref.read(settingsStoreProvider).read();
      final config = await ref.read(credentialStoreProvider).read();
      if (_disposed) return;
      _storageReady = true;
      state = AppState(settings: settings, config: config);
      if (state.configured) await _attach();
    } catch (error) {
      if (!_disposed) {
        final detail = error is TimeoutException
            ? ' (Storage read timed out.)'
            : error is PlatformException && error.details is int
            ? ' (Storage code ${error.details}.)'
            : error is FormatException || error is TypeError
            ? ' (Saved connection data could not be decoded.)'
            : '';
        state = state.copyWith(
          loading: false,
          error:
              'Could not read saved settings or secure credentials. Check your system keychain and try again.$detail',
        );
      }
    }
  }

  void _detach() {
    ++_generation;
    _backgroundDisconnect?.cancel();
    _backgroundDisconnect = null;
    _fallbackRefresh?.cancel();
    unawaited(_updates?.cancel());
    unawaited(_statuses?.cancel());
    unawaited(_connections?.cancel());
    _backend?.dispose();
    _backend = null;
    _revisions.clear();
    _pendingAddresses.clear();
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
    if (backend is LocalLightsRepository) {
      _connections = backend.connectionUpdates.listen((event) {
        unawaited(
          _configurationQueue.run(() async {
            if (_disposed || generation != _generation) return;
            final devices = state.config?.devices;
            final saved = devices
                ?.where((d) => d.slotId == event.previous.slotId)
                .firstOrNull;
            final prior =
                _pendingAddresses[event.previous.slotId]?.current ?? saved;
            if (saved == null ||
                prior == null ||
                !mapEquals(prior.toJson(), event.previous.toJson())) {
              return;
            }
            _pendingAddresses[saved.slotId] = ResolvedConnection(
              saved,
              event.current,
            );
            final updated = [
              for (final device in devices!)
                _pendingAddresses[device.slotId]?.current ?? device,
            ];
            // DHCP can swap the two tubes' old addresses. Wait for both
            // verified resolutions and persist the swap in one atomic write.
            if (updated.map((d) => d.host).toSet().length != updated.length) {
              return;
            }
            try {
              final config = ConnectionConfig(updated);
              await ref.read(credentialStoreProvider).write(config);
              if (!_disposed && generation == _generation) {
                state = state.copyWith(config: config);
                _pendingAddresses.clear();
              }
            } catch (_) {
              if (!_disposed && generation == _generation) {
                state = state.copyWith(
                  error: 'Light reconnected, but its new address could not be saved. Check secure storage access.',
                );
              }
            }
          }),
        );
      });
    }
    state = AppState(
      settings: state.settings,
      config: state.config,
      loading: true,
      timerWarning: state.timerWarning,
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
    _startRefresh();
    await refresh(force: true);
  }

  void _startRefresh() {
    _fallbackRefresh?.cancel();
    _fallbackRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_foreground && state.busy.isEmpty) unawaited(refresh());
    });
  }

  Future<void> refresh({bool force = false}) async {
    if (!_storageReady) {
      await initialize();
      return;
    }
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

  /// Setup-only status queries. Never sends power/color commands or saves an
  /// unverified candidate; each attempt disposes its own transport.
  Future<DeviceConnection> detectTuyaProtocol(
    DeviceConnection device, {
    void Function(TuyaVersion)? onTrying,
    bool Function()? stillWanted,
  }) async {
    if (device.brand != DeviceBrand.tuya) {
      throw const DeviceException(
        DeviceError.invalidUrl,
        'Choose a Wipro / Tuya light.',
      );
    }
    final failures = <String>[];
    for (final version in {device.version, ...TuyaVersion.values}) {
      if (_disposed || (stillWanted != null && !stillWanted())) {
        throw const DeviceException(
          DeviceError.unavailable,
          'Connection check cancelled.',
        );
      }
      final candidate = DeviceConnection.fromJson({
        ...device.toJson(),
        'version': version.name,
      });
      onTrying?.call(version);
      try {
        final light = await inspectDevice(candidate);
        if (!light.available) {
          throw const DeviceException(
            DeviceError.unavailable,
            'No usable light state.',
          );
        }
        return candidate.withAddress(
          host: light.rawAttributes['connection_host'] as String?,
        );
      } on DeviceException catch (error) {
        if (error.kind == DeviceError.unreachable) rethrow;
        // Only our fixed categories reach the UI, never a parser/vendor error.
        final reason = switch (error.kind) {
          DeviceError.timeout =>
            error is TuyaTimeoutException ? error.message : 'No response.',
          DeviceError.unauthorized => 'Local key rejected.',
          DeviceError.malformed =>
            'Reply could not be verified or did not match the light profile.',
          DeviceError.server => 'Request rejected by the light.',
          _ => 'No usable light state.',
        };
        failures.add('${DeviceConnection.versionText(version)}: $reason');
      }
    }
    throw DeviceException(
      DeviceError.unavailable,
      'Could not verify this light with any supported protocol.\n${failures.join('\n')}\nCheck the other light IP, or select the paired light again to refresh its local key.',
    );
  }

  Future<void> saveDevice(DeviceConnection device) =>
      _configurationQueue.run(() => _saveDevice(device));
  Future<void> _saveDevice(DeviceConnection device) async {
    await _ensureStorageReady();
    final light = await inspectDevice(device);
    device = device.withAddress(
      host: light.rawAttributes['connection_host'] as String?,
      macAddress: DeviceConnection.normalizeMac(
        light.rawAttributes['device_mac'],
      ),
    );
    final devices = [
      ...?state.config?.devices.where((d) => d.slotId != device.slotId),
      device,
    ];
    final config = ConnectionConfig(devices);
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

  Future<ConnectionConfig> configurationForTransfer() async {
    await _ensureStorageReady();
    final config = state.config;
    if (config == null || config.devices.isEmpty) {
      throw const DeviceException(
        DeviceError.storage,
        'Connect and save a light first.',
      );
    }
    return config;
  }

  Future<void> importConnections(ConnectionConfig incoming) =>
      _configurationQueue.run(() async {
        await _ensureStorageReady();
        if (incoming.devices.isEmpty) {
          throw const DeviceException(
            DeviceError.invalidUrl,
            'Select a light to import.',
          );
        }
        final slots = incoming.devices.map((d) => d.slotId).toSet();
        // Validate the complete merge before making any persistent change.
        final merged = ConnectionConfig([
          ...?state.config?.devices.where((d) => !slots.contains(d.slotId)),
          ...incoming.devices,
        ]);
        await _saveConfig(merged);
      });

  Future<void> _removeDevice(String slotId) async {
    await _ensureStorageReady();
    final config = ConnectionConfig(
      state.config?.devices.where((d) => d.slotId != slotId).toList() ?? [],
    );
    await _saveConfig(config);
  }

  /// Removes the room card as well as its saved connection, without contacting
  /// or resetting the physical light. removeDevice remains disconnect-only.
  Future<void> deleteLight(String slotId) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    if (!state.settings.slots.any((s) => s.id == slotId)) return;
    final config = ConnectionConfig([
      ...?state.config?.devices.where((d) => d.slotId != slotId),
    ]);
    await _saveConfig(
      config,
      settings: state.settings.copyWith(
        slots: state.settings.slots.where((s) => s.id != slotId).toList(),
      ),
    );
  });

  Future<void> addLight(String name) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    final slot = DeviceSlot.defaults
        .where(
          (candidate) =>
              !state.settings.slots.any((s) => s.id == candidate.id) &&
              !(state.config?.devices.any((d) => d.slotId == candidate.id) ??
                  false),
        )
        .firstOrNull;
    if (slot == null || name.trim().isEmpty || name.trim().length > 80) {
      throw const DeviceException(
        DeviceError.storage,
        'Give your light a name (up to 80 characters). This room supports up to three lights.',
      );
    }
    final settings = state.settings.copyWith(
      demo: false,
      slots: [
        ...state.settings.slots,
        DeviceSlot(id: slot.id, name: name.trim()),
      ],
    );
    await ref.read(settingsStoreProvider).write(settings);
    if (_disposed) return;
    state = state.copyWith(settings: settings);
    await _attach();
  });

  Future<void> _saveConfig(
    ConnectionConfig config, {
    AppSettings? settings,
  }) async {
    final previousConfig = state.config ?? ConnectionConfig([]);
    settings = (settings ?? state.settings).copyWith(demo: false);
    // An explicit setup import may bring back a previously deleted room card.
    settings = settings.copyWith(
      slots: [
        ...settings.slots,
        for (final device in config.devices)
          if (!settings.slots.any((s) => s.id == device.slotId))
            DeviceSlot(id: device.slotId, name: device.name),
      ],
    );
    try {
      await ref.read(credentialStoreProvider).write(config);
      try {
        await ref.read(settingsStoreProvider).write(settings);
      } catch (_) {
        await ref.read(credentialStoreProvider).write(previousConfig);
        rethrow;
      }
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

  Future<void> _ensureStorageReady() async {
    if (!_storageReady) await initialize();
    if (!_storageReady) {
      throw const DeviceException(
        DeviceError.storage,
        'Could not read your saved lights. Retry after unlocking Keychain before changing device connections.',
      );
    }
  }

  Future<void> setForeground(bool foreground) async {
    if (_disposed) return;
    _foreground = foreground;
    if (foreground) {
      _backgroundDisconnect?.cancel();
      _backgroundDisconnect = null;
      if (_backend == null && state.configured) {
        await _attach();
      } else if (_backend != null) {
        _startRefresh();
      }
    } else {
      _fallbackRefresh?.cancel();
      if (_pendingTimerSetups > 0 && _backend != null) {
        // Finish the already-requested native countdown before releasing its
        // socket. Hidden/paused events often arrive as soon as Sleep is tapped.
        // This is a bounded handoff, never an app-side 15-minute alarm.
        _backgroundDisconnect ??= Timer(ref.read(timerSetupGraceProvider), () {
          if (_disposed || _foreground) return;
          state = state.copyWith(
            timerWarning: 'Timer setup was interrupted before it could be confirmed. Check Timers & schedules before relying on automatic turn-off.',
          );
          _suspendConnections();
        });
      } else {
        _suspendConnections();
      }
    }
  }

  void _suspendConnections() {
    _detach();
    state = state.copyWith(
      loading: false,
      connected: false,
      busy: {},
      realtime: ConnectionStatus.disconnected,
    );
  }

  void dismissTimerWarning() {
    state = state.copyWith(clearTimerWarning: true);
  }

  Future<ActionReport> _finishTimerSetup(
    Future<ActionReport> Function() action,
  ) async {
    _pendingTimerSetups++;
    try {
      final report = await action();
      if (!_disposed) {
        state = state.copyWith(
          timerWarning: report.hasFailures
              ? 'Timer setup needs attention: ${report.message}'
              : null,
          clearTimerWarning: !report.hasFailures,
        );
      }
      return report;
    } finally {
      _pendingTimerSetups--;
      if (!_disposed && !_foreground && _pendingTimerSetups == 0) {
        _suspendConnections();
      }
    }
  }

  Future<void> setDemo(bool value) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    final settings = state.settings.copyWith(demo: value);
    await ref.read(settingsStoreProvider).write(settings);
    if (_disposed) return;
    state = AppState(config: state.config, settings: settings);
    await _attach();
  });

  Future<void> setTheme(ThemeMode theme) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    final settings = state.settings.copyWith(theme: theme);
    await ref.read(settingsStoreProvider).write(settings);
    if (!_disposed) state = state.copyWith(settings: settings);
  });

  Future<void> setPreviewTubesSwapped(bool swap) =>
      _configurationQueue.run(() async {
        await _ensureStorageReady();
        final settings = state.settings.copyWith(swapPreviewTubes: swap);
        await ref.read(settingsStoreProvider).write(settings);
        if (!_disposed) state = state.copyWith(settings: settings);
      });

  Future<void> setGenericRoomPreview(bool generic) =>
      _configurationQueue.run(() async {
        await _ensureStorageReady();
        final settings = state.settings.copyWith(genericRoomPreview: generic);
        await ref.read(settingsStoreProvider).write(settings);
        if (!_disposed) state = state.copyWith(settings: settings);
      });

  Future<void> saveScene(LightScene scene) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    final validated = LightScene.fromJson(scene.toJson());
    final scenes = [...state.settings.customScenes];
    final index = scenes.indexWhere((s) => s.id == validated.id);
    if (index < 0) {
      if (scenes.length >= LightScene.maxCustomScenes) {
        throw const DeviceException(
          DeviceError.storage,
          'You can save up to 60 custom scenes. Delete one to make room.',
        );
      }
      scenes.add(validated);
    } else {
      scenes[index] = validated;
    }
    await _saveScenes(scenes);
  });

  Future<void> setRoomScenes(List<String> ids) => _configurationQueue.run(
    () async {
      await _ensureStorageReady();
      final available = state.scenes.map((scene) => scene.id).toSet();
      final settings = state.settings.copyWith(
        roomSceneIds: List.unmodifiable(ids.where(available.contains).toSet()),
      );
      try {
        await ref.read(settingsStoreProvider).write(settings);
      } catch (_) {
        throw const DeviceException(
          DeviceError.storage,
          'Could not save your room scenes. Please try again.',
        );
      }
      if (!_disposed) state = state.copyWith(settings: settings);
    },
  );

  Future<void> deleteScene(String id) => _configurationQueue.run(() async {
    await _ensureStorageReady();
    await _saveScenes(
      state.settings.customScenes.where((s) => s.id != id).toList(),
    );
  });

  Future<void> _saveScenes(List<LightScene> scenes) async {
    final settings = state.settings.copyWith(
      customScenes: List.unmodifiable(scenes),
    );
    try {
      await ref.read(settingsStoreProvider).write(settings);
    } catch (_) {
      throw const DeviceException(
        DeviceError.storage,
        'Could not save scenes. Your previous scenes and light connections are unchanged.',
      );
    }
    if (!_disposed) state = state.copyWith(settings: settings);
  }

  Future<ActionReport> control(DeviceSlot slot, LightCommand command) =>
      _run({slot.id: command});
  Future<ActionReport> controlAll(LightCommand command) =>
      _run({for (final s in state.slots) s.id: command}, skipUnsupported: true);
  Future<ActionReport> applyScene(LightScene scene) => scene.turnOff == null
      ? _run(scene.commands)
      : _finishTimerSetup(() => _run(scene.commands, turnOff: scene.turnOff));

  Future<LightTimerStatus> readTimer(String slotId) async {
    final backend = _backend;
    final slot = state.slots.where((s) => s.id == slotId).firstOrNull;
    if (backend is! LightTimersRepository || slot?.entityId == null) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Connect this light to check its built-in timer.',
      );
    }
    return (backend as LightTimersRepository).readTimer(slot!.entityId!);
  }

  Future<ActionReport> scheduleTimers(
    Set<String> slotIds,
    DateTime endsAt, {
    required bool on,
  }) => _finishTimerSetup(() => _runTimers(slotIds, endsAt: endsAt, on: on));

  Future<ActionReport> cancelLightTimer(String slotId) =>
      _finishTimerSetup(() => _runTimers({slotId}));

  Future<ActionReport> _runTimers(
    Set<String> slotIds, {
    DateTime? endsAt,
    bool on = false,
  }) async {
    final backend = _backend;
    final generation = _generation;
    final targets = state.slots.where((s) => slotIds.contains(s.id)).toList();
    if (state.busy.isNotEmpty) {
      return ActionReport(
        succeeded: [],
        failed: {'Timers': 'Wait for the current action to finish.'},
        skipped: [],
      );
    }
    final succeeded = <String>[];
    final failed = <String, String>{};
    state = state.copyWith(busy: targets.map((s) => s.id).toSet());
    await Future.wait(
      targets.map((slot) async {
        try {
          if (backend is! LightTimersRepository || slot.entityId == null) {
            throw const DeviceException(
              DeviceError.unavailable,
              'Connect this light first.',
            );
          }
          final timers = backend as LightTimersRepository;
          if (endsAt == null) {
            await timers.cancelTimer(slot.entityId!);
          } else {
            await timers.setTimer(slot.entityId!, endsAt, on: on);
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
    return ActionReport(
      succeeded: succeeded,
      failed: failed,
      skipped: [],
      successVerb: endsAt == null ? 'timer cancelled' : 'timer set',
    );
  }

  Future<ActionReport> _run(
    Map<String, LightCommand> commands, {
    bool skipUnsupported = false,
    SceneOffSchedule? turnOff,
  }) async {
    final succeeded = <String>[];
    final failed = <String, String>{};
    final skipped = <String>[];
    var timersConfirmed = 0;
    DateTime? endsAt;
    if (turnOff != null) {
      try {
        final validated = SceneOffSchedule.fromJson(turnOff.toJson());
        endsAt = validated.resolve(DateTime.now());
        countdownSeconds(endsAt);
      } catch (error) {
        return ActionReport(
          succeeded: [],
          failed: {
            'Scene': error is FormatException
                ? 'Choose a valid scene turn-off time.'
                : userMessage(error),
          },
          skipped: [],
        );
      }
    }
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
        var applied = false, commandAttempted = false;
        try {
          void requireCurrent() {
            if (_disposed || generation != _generation) {
              throw const DeviceException(
                DeviceError.unavailable,
                'Scene setup was interrupted. Check the light and its timer before trying again.',
              );
            }
          }

          final needsTimer = endsAt != null && command.service == 'turn_on';
          if (needsTimer) {
            if (backend is! LightTimersRepository) {
              throw const DeviceException(
                DeviceError.unavailable,
                'This light does not support built-in turn-off timers. Scene not applied.',
              );
            }
            final timers = backend as LightTimersRepository;
            final current = await timers.readTimer(light.entityId);
            requireCurrent();
            if (!current.supported) {
              throw DeviceException(
                DeviceError.unavailable,
                '${current.unsupportedReason} Scene not applied.',
              );
            }
            countdownSeconds(endsAt!);
            if (current.active != null) {
              final cancelled = await timers.cancelTimer(light.entityId);
              requireCurrent();
              if (!cancelled.supported || cancelled.active != null) {
                throw timerUnconfirmed;
              }
              countdownSeconds(endsAt!);
            }
          }
          commandAttempted = true;
          await backend.command(light, command);
          applied = true;
          requireCurrent();
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
          if (needsTimer) {
            requireCurrent();
            if (!updated.available || !updated.isOn) {
              throw const DeviceException(
                DeviceError.unavailable,
                'The light did not report being on. Turn-off timer was not set.',
              );
            }
            final status = await (backend as LightTimersRepository).setTimer(
              light.entityId,
              endsAt!,
              on: false,
            );
            requireCurrent();
            final confirmed = status.active;
            if (!status.supported ||
                confirmed == null ||
                confirmed.on ||
                confirmed.endsAt.difference(endsAt!).inSeconds.abs() > 35) {
              throw timerUnconfirmed;
            }
            timersConfirmed++;
          }
          succeeded.add(slot.name);
        } catch (error) {
          failed[slot.name] =
              turnOff != null &&
                  command.service == 'turn_on' &&
                  commandAttempted
              ? applied
                    ? 'Scene applied, but automatic turn-off was not confirmed. ${userMessage(error)} Check Timers before retrying.'
                    : 'Scene change was not confirmed. Automatic turn-off was not set. ${userMessage(error)} Check this light before retrying.'
              : userMessage(error);
        }
      }),
    );
    if (!_disposed && generation == _generation) {
      state = state.copyWith(busy: {});
    }
    return ActionReport(
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      successVerb: timersConfirmed == 0
          ? 'updated'
          : 'updated; $timersConfirmed turn-off ${timersConfirmed == 1 ? 'timer' : 'timers'} confirmed',
    );
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
