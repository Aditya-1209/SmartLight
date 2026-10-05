import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/connection_config.dart';
import '../pairing/tuya_discovery.dart';

class TuyaDiscoveredLight {
  const TuyaDiscoveredLight({required this.deviceId, required this.host});
  final String deviceId, host;
}

typedef TuyaDiscover = Future<List<TuyaDiscoveredLight>> Function();

/// Both tubes share one bounded search, avoiding competing listeners on the
/// fixed Tuya UDP ports. Discovery contains no saved light credentials.
class TuyaLanDiscovery {
  static const _channel = MethodChannel('smartlight/lan_discovery');
  TuyaLanDiscovery({TuyaDiscover? scanner}) : _scan = scanner ?? scan;
  final TuyaDiscover _scan;
  Future<List<TuyaDiscoveredLight>>? _pending;
  Future<List<TuyaDiscoveredLight>> discover() =>
      _pending ??= _scan().whenComplete(() => _pending = null);

  static Future<List<TuyaDiscoveredLight>> scan({
    Duration duration = const Duration(seconds: 8),
  }) async {
    final discovery = TuyaDiscovery();
    Timer? timer;
    int? lease;
    try {
      if (Platform.isAndroid) {
        try {
          lease = await _channel
              .invokeMethod<int>('acquire')
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // Unicast replies/passive reception may still work without a lock.
        }
      }
      final addresses = <String>[];
      try {
        for (final interface in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        )) {
          addresses.addAll(
            interface.addresses
                .map((a) => a.address)
                .where(DeviceConnection.isLocalAddress),
          );
        }
      } on SocketException {
        // Passive broadcasts still work if interface enumeration is blocked.
      }
      final interfaces = addresses.toSet().take(8).toList();
      await discovery.start(interfaces.firstOrNull ?? '0.0.0.0');
      Future<void> probe() async {
        for (final address in interfaces) {
          await discovery.probe(address);
        }
      }

      // The first interface was probed by start; probe the rest as well.
      for (final address in interfaces.skip(1)) {
        await discovery.probe(address);
      }
      timer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(probe());
      });
      await Future<void>.delayed(duration);
      return discovery.addresses.values
          .map(
            (d) => TuyaDiscoveredLight(
              deviceId: d['deviceId'] as String,
              host: d['host'] as String,
            ),
          )
          .toList();
    } finally {
      timer?.cancel();
      discovery.close();
      if (lease != null) {
        try {
          await _channel
              .invokeMethod<void>('release', lease)
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // The activity also releases all leases when it stops.
        }
      }
    }
  }
}
