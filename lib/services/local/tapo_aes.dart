import 'dart:convert';
import 'dart:isolate';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'crypto_utils.dart';

/// Legacy Tapo RSA/AES wire format. References: THIRD_PARTY_NOTICES.md.
class TapoAesHandshake {
  TapoAesHandshake(this._keys);
  final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _keys;

  // RSA generation must not block the Flutter UI thread.
  static Future<TapoAesHandshake> generate() => Isolate.run(() {
    final random = FortunaRandom()..seed(KeyParameter(randomBytes(32)));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          // The legacy device protocol requires a 1024-bit RSA key.
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
          random,
        ),
      );
    return TapoAesHandshake(generator.generateKeyPair());
  });

  String get publicKeyPem {
    final key = _keys.publicKey;
    final rsa = ASN1Sequence(
      elements: [ASN1Integer(key.modulus!), ASN1Integer(key.exponent!)],
    );
    final spki = ASN1SubjectPublicKeyInfo(
      ASN1AlgorithmIdentifier.fromIdentifier('1.2.840.113549.1.1.1'),
      ASN1BitString(stringValues: rsa.encode()),
    );
    final encoded = base64Encode(spki.encode());
    final lines = <String>[
      for (var i = 0; i < encoded.length; i += 64)
        encoded.substring(i, (i + 64).clamp(0, encoded.length)),
    ];
    return '-----BEGIN PUBLIC KEY-----\n${lines.join('\n')}\n-----END PUBLIC KEY-----\n';
  }

  TapoAesCipher finish(String encryptedKey) {
    final encrypted = base64Decode(encryptedKey);
    if (encrypted.length != 128) {
      throw const FormatException('Invalid Tapo RSA key length.');
    }
    try {
      final rsa = PKCS1Encoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(_keys.privateKey));
      final secret = rsa.process(encrypted);
      if (secret.length != 32) {
        throw const FormatException('Invalid Tapo AES key length.');
      }
      return TapoAesCipher(secret.sublist(0, 16), secret.sublist(16));
    } catch (_) {
      throw const FormatException('Invalid Tapo RSA handshake.');
    }
  }
}

class TapoAesCipher {
  TapoAesCipher(this.key, this.iv);
  final List<int> key, iv;

  String encrypt(Map<String, dynamic> data) =>
      base64Encode(aesBlock(utf8.encode(jsonEncode(data)), key, iv: iv));

  Object? decrypt(String data) => jsonDecode(
    utf8.decode(aesBlock(base64Decode(data), key, iv: iv, encrypt: false)),
  );

  static Map<String, String> loginParams(String email, String password) {
    final username = sha1(utf8.encode(email.trim()))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return {
      'username': base64Encode(ascii.encode(username)),
      'password': base64Encode(utf8.encode(password)),
    };
  }
}
