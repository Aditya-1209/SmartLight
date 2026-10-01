import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/connection_config.dart';

class TapoDiscoveredLight {
  const TapoDiscoveredLight({
    required this.host,
    required this.macAddress,
    required this.model,
  });
  final String host, macAddress, model;
}

typedef TapoDiscover = Future<List<TapoDiscoveredLight>> Function();

/// UDP discovery is an address hint only. Never contains account credentials;
/// an authenticated device-info read must verify identity before saving/using it.
/// Packet format reference: python-kasa's public discovery protocol.
class TapoDiscovery {
  static const query = <int>[
    2,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0x46,
    0x3c,
    0xb5,
    0xd3,
  ];

  static TapoDiscoveredLight? decode(
    List<int> packet,
    String source,
    int port,
  ) {
    if (port != 20002 ||
        !DeviceConnection.isLocalAddress(source) ||
        packet.length < 18 ||
        packet.length > 8192) {
      return null;
    }
    try {
      final data = jsonDecode(utf8.decode(packet.sublist(16)));
      if (data is! Map || data['error_code'] != 0) return null;
      final result = data['result'];
      if (result is! Map || result['device_type'] != 'SMART.TAPOBULB') {
        return null;
      }
      final mac = DeviceConnection.normalizeMac(result['mac']);
      final model = result['device_model'];
      if (mac == null ||
          model is! String ||
          model.isEmpty ||
          model.length > 64) {
        return null;
      }
      // The payload's IP is untrusted; use only the local UDP sender.
      return TapoDiscoveredLight(host: source, macAddress: mac, model: model);
    } catch (_) {
      return null;
    }
  }

  static Future<List<TapoDiscoveredLight>> discover({
    Duration duration = const Duration(seconds: 3),
  }) async {
    final sockets = <RawDatagramSocket>[];
    final timers = <Timer>[];
    final lights = <String, TapoDiscoveredLight>{};
    try {
      final addresses = <String>{'0.0.0.0'};
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
        /* Default route remains usable. */
      }
      for (final address in addresses.take(8)) {
        try {
          final socket = await RawDatagramSocket.bind(address, 0);
          sockets.add(socket);
          socket.broadcastEnabled = true;
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? packet;
            while ((packet = socket.receive()) != null) {
              final light = decode(
                packet!.data,
                packet.address.address,
                packet.port,
              );
              if (light != null && lights.length < 128) {
                lights['${light.macAddress}/${light.host}'] = light;
              }
            }
          }, onError: (Object _) {});
          void send() {
            try {
              socket.send(query, InternetAddress('255.255.255.255'), 20002);
            } on SocketException {
              /* Another interface may respond. */
            }
          }

          send();
          timers.add(Timer.periodic(const Duration(seconds: 1), (_) => send()));
        } on SocketException {
          /* Discovery may be unavailable on one interface. */
        }
      }
      if (sockets.isNotEmpty) await Future<void>.delayed(duration);
      return lights.values.toList()..sort((a, b) => a.host.compareTo(b.host));
    } finally {
      for (final timer in timers) {
        timer.cancel();
      }
      for (final socket in sockets) {
        socket.close();
      }
    }
  }
}
