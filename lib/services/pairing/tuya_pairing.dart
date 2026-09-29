import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/connection_config.dart';

/// Sensitive setup result. Never log or serialize it outside secure storage.
class PairedTuyaDevice {
  PairedTuyaDevice.fromMap(Map<dynamic, dynamic> data)
    : deviceId = data['deviceId'] as String? ?? '',
      name = data['name'] as String? ?? 'Wipro light',
      localKey = data['localKey'] as String? ?? '',
      host = DeviceConnection.isLocalAddress(data['host'] as String? ?? '')
          ? data['host'] as String
          : '',
      version = switch (data['version']) {
        '3.3' => TuyaVersion.v33,
        '3.4' => TuyaVersion.v34,
        '3.5' => TuyaVersion.v35,
        _ => null,
      },
      profile = (data['dpIds'] as List? ?? []).map((e) => '$e').contains('20')
          ? TuyaProfile.modern
          : (data['dpIds'] as List? ?? []).map((e) => '$e').contains('1')
          ? TuyaProfile.legacy
          : null;

  final String deviceId, name, host, localKey;
  final TuyaVersion? version;
  final TuyaProfile? profile;
  bool get hasLocalKey =>
      deviceId.isNotEmpty && utf8.encode(localKey).length == 16;
  @override
  String toString() => 'PairedTuyaDevice(credentials redacted)';
}

class TuyaPairing {
  TuyaPairing({MethodChannel? channel, FlutterSecureStorage? storage})
    : _channel = channel ?? const MethodChannel('smartlight/tuya_pairing'),
      _storage = storage ?? const FlutterSecureStorage();
  final MethodChannel _channel;
  final FlutterSecureStorage _storage;
  static const _profileKey = 'smartlight.tuya_pairing_profile.v1';

  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<PairedTuyaDevice>> prepare() async {
    var raw = await _storage.read(key: _profileKey);
    if (raw == null) {
      final random = Random.secure();
      String randomId() => List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      raw = jsonEncode({'uid': randomId(), 'password': randomId()});
      // Persist before registering so a timeout/retry cannot create orphan accounts.
      await _storage.write(key: _profileKey, value: raw);
    }
    final profile = jsonDecode(raw) as Map<String, dynamic>;
    final data = await _channel.invokeListMethod<dynamic>('prepare', profile);
    return (data ?? [])
        .map((value) => PairedTuyaDevice.fromMap(value as Map))
        .toList();
  }

  Future<void> prepareToken() async {
    await _channel.invokeMethod<void>('permissions');
    await _channel.invokeMethod<void>('token');
  }

  Future<PairedTuyaDevice> pair({
    required String ssid,
    required String password,
    required String mode,
  }) async {
    final data = await _channel.invokeMapMethod<dynamic, dynamic>('pair', {
      'ssid': ssid,
      'password': password,
      'mode': mode,
    });
    if (data == null) {
      throw PlatformException(
        code: 'missing_device',
        message: 'No light was returned.',
      );
    }
    return PairedTuyaDevice.fromMap(data);
  }

  Future<void> wifiSettings() => _channel.invokeMethod<void>('wifiSettings');
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
  Future<void> close() => _channel.invokeMethod<void>('close');
}
