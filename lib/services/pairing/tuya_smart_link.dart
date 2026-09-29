import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tuya_cloud_setup.dart';

/// Tuya EZ packet-length encoding, ported from @tuyapi/link 0.5.0 (MIT).
/// See THIRD_PARTY_NOTICES.md. No Node or mobile SDK is required at runtime.
class TuyaSmartLink {
  RawDatagramSocket? _socket;
  bool _cancelled = false;

  static List<int> encode({
    required String ssid,
    required String password,
    required String region,
    required String token,
    required String secret,
  }) {
    final wifi = utf8.encode(ssid), pass = utf8.encode(password);
    final auth = utf8.encode('$region$token$secret');
    if (wifi.isEmpty ||
        wifi.length > 32 ||
        pass.length > 63 ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(region) ||
        utf8.encode(token).length != 8 ||
        utf8.encode(secret).length != 4) {
      throw const TuyaSetupException(
        'Unsupported Wi-Fi details or Tuya pairing token.',
      );
    }
    final raw = [pass.length, ...pass, auth.length, ...auth, ...wifi];
    int crc8(List<int> data) {
      var crc = 0;
      for (final byte in data) {
        crc ^= byte;
        for (var i = 0; i < 8; i++) {
          crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0x8c : 0);
        }
      }
      return crc;
    }

    final lengthCrc = crc8([raw.length]);
    final result = [
      raw.length ~/ 16 | 16,
      raw.length % 16 | 32,
      lengthCrc ~/ 16 | 48,
      lengthCrc % 16 | 64,
    ];
    for (var i = 0; i < raw.length; i += 4) {
      final chunk = [
        i ~/ 4,
        for (var j = 0; j < 4; j++) i + j < raw.length ? raw[i + j] : 0,
      ];
      result.addAll([
        crc8(chunk) % 128 | 128,
        chunk[0] | 128,
        for (final byte in chunk.skip(1)) byte | 256,
      ]);
    }
    return result;
  }

  Future<void> send({
    required String ssid,
    required String password,
    required String region,
    required String token,
    required String secret,
    required String bindAddress,
  }) async {
    final lengths = encode(
      ssid: ssid,
      password: password,
      region: region,
      token: token,
      secret: secret,
    );
    if (_cancelled) return;
    final socket = await RawDatagramSocket.bind(bindAddress, 0);
    if (_cancelled) {
      socket.close();
      return;
    }
    _socket = socket..broadcastEnabled = true;
    final destination = InternetAddress('255.255.255.255');
    Future<void> sendLength(int size, [int delay = 2]) async {
      if (_cancelled) return;
      if (socket.send(Uint8List(size), destination, 30011) != size) {
        throw const TuyaSetupException(
          'Wi-Fi setup could not be sent. Check the selected Mac network connection.',
        );
      }
      await Future<void>.delayed(Duration(milliseconds: delay));
    }

    try {
      // Repeat the reference preamble/data cycle until the caller cancels or
      // the bounded pairing deadline ends. Each send observes cancellation.
      while (!_cancelled) {
        for (var i = 0; i < 32 && !_cancelled; i++) {
          final preamble = [1, 3, 6, 10, 1, 3, 6, 10];
          for (var j = 0; j < preamble.length; j++) {
            await sendLength(preamble[j], j == 7 ? 40 : 2);
          }
        }
        for (var i = 0; i < 10 && !_cancelled; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 160));
          for (final size in lengths) {
            if (_cancelled) break;
            await sendLength(size);
          }
        }
      }
    } finally {
      socket.close();
      if (_socket == socket) _socket = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _socket?.close();
    _socket = null;
  }
}
