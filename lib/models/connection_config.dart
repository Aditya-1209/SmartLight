import 'dart:convert';
import 'dart:io';

import '../services/device_exception.dart';

enum DeviceBrand { tapo, tuya }

enum TuyaVersion { v33, v34, v35 }

enum TuyaProfile { modern, legacy }

/// Credentials are serialized for secure storage or authenticated, encrypted transfer.
class DeviceConnection {
  DeviceConnection({
    required this.slotId,
    required this.name,
    required this.brand,
    required String host,
    this.email = '',
    this.password = '',
    this.deviceId = '',
    this.localKey = '',
    this.version = TuyaVersion.v33,
    this.profile = TuyaProfile.modern,
    this.minKelvin = 2700,
    this.maxKelvin = 6500,
  }) : host = host.trim() {
    if (!{'tube1', 'tube2', 'strip'}.contains(slotId) || name.trim().isEmpty) {
      throw const DeviceException(
        DeviceError.invalidUrl,
        'Choose a room slot and a device name.',
      );
    }
    if (!isLocalAddress(this.host)) {
      throw const DeviceException(
        DeviceError.invalidUrl,
        'Enter the light’s local IPv4 address, such as 192.168.1.50.',
      );
    }
    if (brand == DeviceBrand.tapo &&
        (email.trim().isEmpty || password.isEmpty)) {
      throw const DeviceException(
        DeviceError.unauthorized,
        'Enter your Tapo account email and password.',
      );
    }
    if (brand == DeviceBrand.tuya &&
        (deviceId.trim().isEmpty || utf8.encode(localKey).length != 16)) {
      throw const DeviceException(
        DeviceError.unauthorized,
        'Enter the device ID and its 16-byte local key. This is not your Wipro password.',
      );
    }
    if (minKelvin < 1500 || maxKelvin > 10000 || minKelvin >= maxKelvin) {
      throw const DeviceException(
        DeviceError.invalidUrl,
        'Enter a valid warm/cool range (1500–10000 K).',
      );
    }
  }
  final String slotId, name, host, email, password, deviceId, localKey;
  final DeviceBrand brand;
  final TuyaVersion version;
  final TuyaProfile profile;
  final int minKelvin, maxKelvin;
  String get entityId => 'light.$slotId';
  String get protocolLabel => brand == DeviceBrand.tapo
      ? 'Tapo · Auto'
      : 'Tuya ${versionText(version)}';
  static String versionText(TuyaVersion version) => switch (version) {
    TuyaVersion.v33 => '3.3',
    TuyaVersion.v34 => '3.4',
    TuyaVersion.v35 => '3.5',
  };
  // Literal private/link-local addresses prevent credential redirects and DNS rebinding.
  static bool isLocalAddress(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;
    final b = ip.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }

  Map<String, dynamic> toJson() => {
    'slotId': slotId,
    'name': name,
    'brand': brand.name,
    'host': host,
    'email': email,
    'password': password,
    'deviceId': deviceId,
    'localKey': localKey,
    'version': version.name,
    'profile': profile.name,
    'minKelvin': minKelvin,
    'maxKelvin': maxKelvin,
  };
  factory DeviceConnection.fromJson(Map<String, dynamic> json) =>
      DeviceConnection(
        slotId: json['slotId'] as String,
        name: json['name'] as String,
        brand: DeviceBrand.values.byName(json['brand'] as String),
        host: json['host'] as String,
        email: json['email'] as String? ?? '',
        password: json['password'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        localKey: json['localKey'] as String? ?? '',
        version: TuyaVersion.values.byName(json['version'] as String? ?? 'v33'),
        profile: TuyaProfile.values.byName(
          json['profile'] as String? ?? 'modern',
        ),
        minKelvin: json['minKelvin'] as int? ?? 2700,
        maxKelvin: json['maxKelvin'] as int? ?? 6500,
      );
  @override
  String toString() => 'DeviceConnection($slotId, credentials redacted)';
}

class ConnectionConfig {
  ConnectionConfig(List<DeviceConnection> devices)
    : devices = List.unmodifiable(devices) {
    if (devices.length > 3 ||
        devices.map((d) => d.slotId).toSet().length != devices.length ||
        devices.map((d) => d.host).toSet().length != devices.length) {
      throw const DeviceException(
        DeviceError.invalidUrl,
        'Each light must have its own room slot and IP address.',
      );
    }
  }
  final List<DeviceConnection> devices;
  Map<String, dynamic> toJson() => {
    'version': 2,
    'devices': devices.map((d) => d.toJson()).toList(),
  };
  factory ConnectionConfig.fromJson(Map<String, dynamic> json) =>
      ConnectionConfig(
        (json['devices'] as List)
            .map(
              (d) => DeviceConnection.fromJson(
                Map<String, dynamic>.from(d as Map),
              ),
            )
            .toList(),
      );
  @override
  String toString() =>
      'ConnectionConfig(${devices.length} devices, credentials redacted)';
}
