import 'dart:convert';
import 'dart:io';

import '../../models/connection_config.dart';
import '../local/crypto_utils.dart';
import '../local/tuya_protocol.dart';

/// Short-lived listener used during pairing and address recovery. Broadcasts are hints; the
/// existing authenticated TCP connection must succeed before a light is saved.
class TuyaDiscovery {
  final _sockets = <RawDatagramSocket>[];
  final devices = <String, Map<String, dynamic>>{};
  // Keep every ID/address pair so conflicting announcements remain ambiguous.
  final addresses = <String, Map<String, dynamic>>{};
  bool _closed = false;
  static final _key = md5(ascii.encode('yGAdlopoPVldABfn'));

  static Map<String, dynamic>? decode(List<int> packet, String source) {
    if (!DeviceConnection.isLocalAddress(source) || packet.length > 8192) {
      return null;
    }
    try {
      List<int> payload;
      if (packet.length >= 24 && readU32(packet, 0) == 0x55aa) {
        if (readU32(packet, 12) + 16 != packet.length ||
            readU32(packet, packet.length - 4) != 0xaa55 ||
            crc32(packet.sublist(0, packet.length - 8)) !=
                readU32(packet, packet.length - 8)) {
          return null;
        }
        payload = packet.sublist(16, packet.length - 8);
        if (payload.length >= 4 && payload.take(4).every((v) => v == 0)) {
          payload = payload.sublist(4);
        }
        if (payload.isEmpty) return null;
        if (payload.first != 123) {
          payload = aesBlock(payload, _key, encrypt: false);
        }
      } else if (packet.length >= 50 && readU32(packet, 0) == 0x6699) {
        payload = TuyaCodec(
          TuyaVersion.v35,
          _key,
        ).decode(packet, response: false).payload;
        if (payload.length > 4 && payload.take(4).every((v) => v == 0)) {
          payload = payload.sublist(4);
        }
      } else {
        payload = aesBlock(packet, _key, encrypt: false);
      }
      final decoded = jsonDecode(
        utf8.decode(payload).replaceFirst(RegExp(r'\x00+$'), ''),
      );
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['gwId'] ?? decoded['devId'];
      if (id is! String || id.isEmpty || id.length > 128) return null;
      // Use the LAN sender, never an untrusted address embedded in a datagram.
      return {'deviceId': id, 'host': source, 'version': decoded['version']};
    } catch (_) {
      return null;
    }
  }

  Future<void> start(String bindAddress) async {
    for (final port in [6666, 6667, 7000]) {
      if (_closed) return;
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
        if (_closed) {
          socket.close();
          return;
        }
        _sockets.add(socket);
        socket.listen((event) {
          if (event != RawSocketEvent.read || _closed) return;
          Datagram? datagram;
          for (
            var received = 0;
            received < 128 && (datagram = socket.receive()) != null;
            received++
          ) {
            final data = decode(datagram!.data, datagram.address.address);
            if (data != null && addresses.length < 128) {
              final id = data['deviceId'] as String;
              devices[id] = data;
              addresses['$id/${data['host']}'] = data;
            }
          }
        }, onError: (Object _) {});
      } on SocketException {
        /* Manual IP entry remains available. */
      }
    }
    await probe(bindAddress);
  }

  Future<void> probe(String bindAddress) async {
    if (_closed || !DeviceConnection.isLocalAddress(bindAddress)) return;
    try {
      final socket = await RawDatagramSocket.bind(bindAddress, 0);
      if (_closed) {
        socket.close();
        return;
      }
      _sockets.add(socket);
      socket.broadcastEnabled = true;
      final request = TuyaCodec(TuyaVersion.v35, _key).encode(
        0,
        0x25,
        utf8.encode(jsonEncode({'from': 'app', 'ip': bindAddress})),
      );
      socket.send(request, InternetAddress('255.255.255.255'), 7000);
    } on SocketException {
      /* Passive broadcasts or manual entry still work. */
    }
  }

  void close() {
    _closed = true;
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
  }
}
