import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

Uint8List bytes(Iterable<int> values) => Uint8List.fromList(values.toList());
Uint8List randomBytes(int count) {
  final random = Random.secure();
  return bytes(List.generate(count, (_) => random.nextInt(256)));
}

Uint8List sha256(List<int> data) => bytes(hash.sha256.convert(data).bytes);
Uint8List sha1(List<int> data) => bytes(hash.sha1.convert(data).bytes);
Uint8List md5(List<int> data) => bytes(hash.md5.convert(data).bytes);
Uint8List hmac256(List<int> key, List<int> data) =>
    bytes(hash.Hmac(hash.sha256, key).convert(data).bytes);
Uint8List u32(int value) =>
    (ByteData(4)..setUint32(0, value & 0xffffffff)).buffer.asUint8List();
int readU32(List<int> value, int offset) =>
    ByteData.sublistView(bytes(value), offset, offset + 4).getUint32(0);
bool equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List aesBlock(
  List<int> input,
  List<int> key, {
  bool encrypt = true,
  List<int>? iv,
  bool padding = true,
}) {
  final BlockCipher cipher = iv == null
      ? ECBBlockCipher(AESEngine())
      : CBCBlockCipher(AESEngine());
  final params = iv == null
      ? KeyParameter(bytes(key))
      : ParametersWithIV(KeyParameter(bytes(key)), bytes(iv));
  cipher.init(encrypt, params);
  var data = bytes(input);
  if (encrypt && padding) {
    final pad = 16 - data.length % 16;
    data = bytes([...data, ...List.filled(pad, pad)]);
  }
  if (data.isEmpty || data.length % 16 != 0) {
    throw const FormatException('Invalid encrypted block size.');
  }
  final result = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, result, i);
  }
  if (!encrypt && padding) {
    final pad = result.last;
    if (pad < 1 ||
        pad > 16 ||
        !result.sublist(result.length - pad).every((b) => b == pad)) {
      throw const FormatException('Invalid encryption padding.');
    }
    return result.sublist(0, result.length - pad);
  }
  return result;
}

Uint8List aesGcm(
  List<int> input,
  List<int> key,
  List<int> iv, {
  List<int> aad = const [],
  bool encrypt = true,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      encrypt,
      AEADParameters(KeyParameter(bytes(key)), 128, bytes(iv), bytes(aad)),
    );
  return cipher.process(bytes(input));
}

int crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
