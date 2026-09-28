import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/connection_config.dart';

abstract interface class CredentialStore {
  Future<ConnectionConfig?> read();
  Future<void> write(ConnectionConfig config);
}

class SecureStorageService implements CredentialStore {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // This app does not share credentials with other apps. The macOS login
            // Keychain works without a distribution provisioning profile.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'smartlight.local_devices.v2';
  @override
  Future<ConnectionConfig?> read() async {
    final value = await _storage
        .read(key: _key)
        .timeout(const Duration(seconds: 10));
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    return ConnectionConfig.fromJson(data);
  }

  @override
  Future<void> write(ConnectionConfig config) => _storage
      .write(key: _key, value: jsonEncode(config.toJson()))
      .timeout(const Duration(seconds: 10));
}
