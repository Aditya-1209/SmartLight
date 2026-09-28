import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/mock_home_assistant.dart';
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
  MockHomeAssistant? backend,
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
      (_, _) => backend ?? MockHomeAssistant(latency: Duration.zero),
    ),
  ],
);
