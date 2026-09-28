import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/demo_lights.dart';
import 'package:smart_light/services/secure_storage_service.dart';

class MemoryCredentials implements CredentialStore {
  ConnectionConfig? config;
  @override
  Future<ConnectionConfig?> read() async => config;
  @override
  Future<void> write(ConnectionConfig value) async {
    config = value;
  }
}

class MemorySettings implements SettingsStore {
  MemorySettings([this.value = const AppSettings()]);
  AppSettings value;
  @override
  Future<AppSettings> read() async => value;
  @override
  Future<void> write(AppSettings settings) async {
    value = settings;
  }
}

ProviderContainer testContainer({
  bool demo = true,
  DemoLights? backend,
  MemorySettings? settings,
  MemoryCredentials? credentials,
}) => ProviderContainer(
  overrides: [
    credentialStoreProvider.overrideWithValue(
      credentials ?? MemoryCredentials(),
    ),
    settingsStoreProvider.overrideWithValue(
      settings ?? MemorySettings(AppSettings(demo: demo)),
    ),
    backendFactoryProvider.overrideWithValue(
      (config, demo) =>
          backend ??
          (demo ? DemoLights(latency: Duration.zero) : ConfiguredDemo(config!)),
    ),
  ],
);

DeviceConnection tapoConfig({String name = 'Tapo Strip'}) => DeviceConnection(
  slotId: 'strip',
  name: name,
  brand: DeviceBrand.tapo,
  host: '192.168.1.50',
  email: 'test@example.com',
  password: 'test-password',
);

class ConfiguredDemo extends DemoLights {
  ConfiguredDemo(this.config) : super(latency: Duration.zero);
  final ConnectionConfig config;
  @override
  Future<List<LightEntity>> getLights() async =>
      Future.wait(config.devices.map((d) => getLight(d.entityId)));
  @override
  Future<LightEntity> getLight(String id) async {
    final original = await super.getLight('light.tapo_strip');
    return LightEntity(
      entityId: id,
      friendlyName: 'Tapo Strip',
      state: original.state,
      attributes: original.rawAttributes,
    );
  }
}
