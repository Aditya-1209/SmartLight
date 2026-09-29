import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../models/connection_config.dart';
import 'local/crypto_utils.dart' as crypto;

class SetupTransferException implements Exception {
  const SetupTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Portable, authenticated envelope. It contains saved light connections only;
/// Wi-Fi passwords and Tuya pairing/developer profiles are never exported.
class SetupTransfer {
  const SetupTransfer();
  static const prefix = 'SMARTLIGHT1.';
  static const maxCodeLength = 16384;
  static const _maxPlaintext = 10000;
  static const _iterations = 600000;
  static final _aad = utf8.encode('SmartLight setup transfer v1');

  static bool validPassword(String password) =>
      password.trim().length >= 12 && utf8.encode(password).length <= 256;

  Future<String> seal(ConnectionConfig config, String password) =>
      compute(_seal, (config, password));

  Future<ConnectionConfig> open(String code, String password) =>
      compute(_open, (code, password));

  static Uint8List _key(String password, Uint8List salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String _seal((ConnectionConfig, String) input) {
    final (config, password) = input;
    if (!validPassword(password)) {
      throw const SetupTransferException(
        'Use a transfer password of at least 12 characters.',
      );
    }
    if (config.devices.isEmpty) {
      throw const SetupTransferException(
        'Connect and save a light before creating a setup code.',
      );
    }
    final plain = utf8.encode(jsonEncode(config.toJson()));
    if (plain.length > _maxPlaintext) {
      throw const SetupTransferException(
        'These connection details are too large to transfer.',
      );
    }
    final salt = crypto.randomBytes(16), nonce = crypto.randomBytes(12);
    final key = _key(password, salt);
    try {
      final ciphertext = crypto.aesGcm(plain, key, nonce, aad: _aad);
      return '$prefix${base64Url.encode([...salt, ...nonce, ...ciphertext])}';
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static ConnectionConfig _open((String, String) input) {
    final (raw, password) = input;
    // Bound work before decoding or deriving a key. The cost is fixed, never
    // supplied by an untrusted envelope.
    if (raw.length > maxCodeLength || !validPassword(password)) {
      throw const SetupTransferException(
        'Check the setup code and transfer password.',
      );
    }
    final code = raw.trim();
    if (!code.startsWith(prefix)) {
      throw const SetupTransferException(
        'Paste a SmartLight setup code beginning with SMARTLIGHT1.',
      );
    }
    Uint8List? key;
    try {
      final packet = base64Url.decode(code.substring(prefix.length));
      if (packet.length < 45 || packet.length > _maxPlaintext + 44) {
        throw const FormatException();
      }
      final salt = packet.sublist(0, 16), nonce = packet.sublist(16, 28);
      key = _key(password, salt);
      final plain = crypto.aesGcm(
        packet.sublist(28),
        key,
        nonce,
        aad: _aad,
        encrypt: false,
      );
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map<String, dynamic> || json['version'] != 2) {
        throw const FormatException();
      }
      final config = ConnectionConfig.fromJson(json);
      if (config.devices.isEmpty) throw const FormatException();
      return config;
    } catch (_) {
      // Authentication, decoding and model validation deliberately expose no
      // decrypted data or parser exceptions.
      throw const SetupTransferException(
        'The password is incorrect or the setup code is invalid.',
      );
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }
}
