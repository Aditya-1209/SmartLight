import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/connection_config.dart';
import '../local/crypto_utils.dart' show randomBytes;
import 'tuya_cloud_setup.dart';
import 'tuya_discovery.dart';
import 'tuya_pairing.dart';
import 'tuya_smart_link.dart';

class DesktopTuyaPairing {
  DesktopTuyaPairing({
    FlutterSecureStorage? storage,
    TuyaCloudSetup Function(TuyaCloudConfig)? apiFactory,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           ),
       _apiFactory = apiFactory ?? TuyaCloudSetup.new;
  final FlutterSecureStorage _storage;
  final TuyaCloudSetup Function(TuyaCloudConfig) _apiFactory;
  static const _configKey = 'smartlight.mac_tuya_setup.v1';
  TuyaCloudSetup? _api;
  TuyaSmartLink? _sender;
  TuyaDiscovery? _discovery;
  String? _uid;
  int _generation = 0;
  bool _closed = false;

  Future<TuyaCloudConfig?> savedConfig() async {
    final raw = await _storage.read(key: _configKey);
    return raw == null
        ? null
        : TuyaCloudConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<Map<String, String>> networkAddresses() async => {
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ))
      for (final address in interface.addresses)
        if (DeviceConnection.isLocalAddress(address.address) &&
            !interface.name.startsWith('utun'))
          address.address: '${interface.name} · ${address.address}',
  };

  Future<List<PairedTuyaDevice>> prepare(TuyaCloudConfig config) async {
    cancel();
    final generation = _generation;
    if (!config.valid) {
      throw const TuyaSetupException(
        'Enter the cloud Access ID, Access Secret and app schema.',
      );
    }
    final api = _api = _apiFactory(config);
    // Verify this exact project/app link before asking the user to reset a tube.
    await api.request('GET', '/v1.0/apps/${config.schema}');
    _check(generation);
    final profileKey =
        'smartlight.mac_tuya_profile.${sha256.convert(utf8.encode('${TuyaCloudConfig.host}:${config.clientId}:${config.schema}'))}';
    var raw = await _storage.read(key: profileKey);
    _check(generation);
    if (raw == null) {
      String randomId() =>
          randomBytes(24)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
      raw = jsonEncode({'username': randomId(), 'password': randomId()});
      await _storage.write(key: profileKey, value: raw);
      _check(generation);
    }
    final profile = jsonDecode(raw) as Map<String, dynamic>;
    var uid = profile['uid'] as String?;
    if (uid == null) {
      final user = await api.request(
        'POST',
        '/v1.0/apps/${config.schema}/user',
        body: {
          'country_code': '91',
          'username': profile['username'],
          'password': md5
              .convert(utf8.encode(profile['password'] as String))
              .toString(),
          'username_type': 3,
          'nick_name': 'SmartLight Mac',
          'time_zone_id': 'Asia/Kolkata',
        },
      );
      _check(generation);
      if (user is! Map || user['uid'] is! String) {
        throw const TuyaSetupException(
          'Tuya did not create the pairing profile.',
        );
      }
      uid = user['uid'] as String;
      profile['uid'] = uid;
      await _storage.write(key: profileKey, value: jsonEncode(profile));
    }
    _check(generation);
    _uid = uid;
    await _storage.write(key: _configKey, value: jsonEncode(config.toJson()));
    _check(generation);
    // Confirm the pairing endpoint is authorized before any physical reset.
    await _newToken(api, uid);
    _check(generation);
    final devices = await api.request(
      'GET',
      '/v1.0/users/${Uri.encodeComponent(uid)}/devices',
    );
    _check(generation);
    return devices is List
        ? [for (final data in devices.whereType<Map>()) _device(data)]
        : [];
  }

  Future<Map> _newToken(TuyaCloudSetup api, String uid) async {
    final token = await api.request(
      'POST',
      '/v1.0/device/paring/token',
      body: {'uid': uid, 'time_zone_id': 'Asia/Kolkata', 'paring_type': 'EZ'},
    );
    if (token is! Map ||
        token['token'] is! String ||
        token['region'] is! String ||
        token['secret'] is! String) {
      throw const TuyaSetupException(
        'Tuya returned an unsupported pairing token.',
      );
    }
    return token;
  }

  Future<PairedTuyaDevice> pair({
    required String ssid,
    required String password,
    required String bindAddress,
  }) async {
    final api = _api, uid = _uid, generation = _generation;
    if (api == null || uid == null) {
      throw const TuyaSetupException('Check setup again before pairing.');
    }
    if (!(await networkAddresses()).containsKey(bindAddress)) {
      throw const TuyaSetupException(
        'The selected Mac Wi-Fi address changed. Check setup again.',
      );
    }
    _check(generation);
    final token = await _newToken(api, uid);
    _check(generation);
    final discovery = _discovery = TuyaDiscovery();
    final sender = _sender = TuyaSmartLink();
    Object? sendError;
    Future<void>? sending;
    try {
      await discovery.start(bindAddress);
      _check(generation);
      sending = sender
          .send(
            ssid: ssid,
            password: password,
            bindAddress: bindAddress,
            region: token['region'] as String,
            token: token['token'] as String,
            secret: token['secret'] as String,
          )
          .catchError((Object error) {
            sendError = error;
          });
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        _check(generation);
        if (sendError != null) {
          throw const TuyaSetupException(
            'The Mac could not send pairing data. Check Wi-Fi and local network access.',
          );
        }
        final result = await api.request(
          'GET',
          '/v1.0/device/paring/tokens/${Uri.encodeComponent(token['token'] as String)}',
        );
        _check(generation);
        if (result is Map &&
            result['success'] is List &&
            (result['success'] as List).isNotEmpty) {
          sender.cancel();
          final entry = (result['success'] as List).first as Map;
          final id = entry['device_id'] ?? entry['id'];
          if (id is! String) {
            throw const TuyaSetupException(
              'Tuya did not return the paired device ID.',
            );
          }
          final details = await api.request(
            'GET',
            '/v1.0/devices/${Uri.encodeComponent(id)}',
          );
          _check(generation);
          if (details is! Map) {
            throw const TuyaSetupException(
              'Could not retrieve this light’s local key. Reopen setup to recover it.',
            );
          }
          return _device(details, discovery.devices[id]);
        }
        if (result is Map &&
            result['failed'] is List &&
            (result['failed'] as List).isNotEmpty) {
          throw const TuyaSetupException(
            'Tuya reported that the light could not pair. Check its pairing mode and Wi-Fi password.',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      throw const TuyaSetupException(
        'No light completed pairing. Check fast blinking and 2.4 GHz Wi-Fi. This Wipro firmware may not support desktop EZ pairing. Reopen setup before resetting again; a late pairing may already be saved.',
      );
    } finally {
      sender.cancel();
      discovery.close();
      await sending;
    }
  }

  PairedTuyaDevice _device(Map data, [Map? lan]) => PairedTuyaDevice.fromMap({
    'deviceId': data['id'] ?? data['device_id'],
    'name': data['name'],
    'localKey': data['local_key'],
    'host': lan?['host'] ?? data['ip'],
    'version': lan?['version'],
  });

  void _check(int generation) {
    if (_closed || generation != _generation) {
      throw const TuyaSetupException('Setup cancelled.');
    }
  }

  void cancel() {
    _generation++;
    _api?.close();
    _api = null;
    _uid = null;
    _sender?.cancel();
    _discovery?.close();
  }

  void close() {
    _closed = true;
    cancel();
  }
}
