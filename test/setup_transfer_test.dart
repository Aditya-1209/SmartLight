import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/services/setup_transfer.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const transfer = SetupTransfer();
  const password = 'four synthetic test words';
  test('reads an independent Python PBKDF2/AES-GCM fixture', () async {
    final fixture = jsonDecode(
      File('test/fixtures/setup_transfer.json').readAsStringSync(),
    ) as Map;
    final result = await transfer.open(fixture['code'], fixture['password']);
    expect(result.devices.single.name, 'Fixture tube');
    expect(result.devices.single.localKey, '0123456789abcdef');
    expect(result.devices.single.version, TuyaVersion.v35);
  });
  test(
    'encrypted transfer round trips credentials and uses fresh randomness',
    () async {
      final config = ConnectionConfig([tapoConfig()]);
      final a = await transfer.seal(config, password);
      final b = await transfer.seal(config, password);
      expect(a, isNot(b));
      expect(a.length, lessThan(SetupTransfer.maxCodeLength));
      expect(a, startsWith(SetupTransfer.prefix));
      expect(a, isNot(contains('test-password')));
      expect(
        (await transfer.open(' $a\n', password)).toJson(),
        config.toJson(),
      );
    },
  );
  test(
    'wrong password and modifications are rejected without leaking data',
    () async {
      final fixture = jsonDecode(
        File('test/fixtures/setup_transfer.json').readAsStringSync(),
      ) as Map;
      final code = fixture['code'] as String;
      final altered = base64Url.decode(
        code.substring(SetupTransfer.prefix.length),
      );
      altered[40] ^= 1;
      for (final input in [
        (code, 'a different password'),
        (
          '${SetupTransfer.prefix}${base64Url.encode(altered)}',
          fixture['password'] as String,
        ),
      ]) {
        await expectLater(
          transfer.open(input.$1, input.$2),
          throwsA(
            isA<SetupTransferException>().having(
              (e) => e.message,
              'safe message',
              allOf(contains('incorrect'), isNot(contains('0123456789abcdef'))),
            ),
          ),
        );
      }
    },
  );
  test(
    'invalid sizes, formats, passwords and empty exports fail safely',
    () async {
      for (final code in [
        'plain credentials',
        'SMARTLIGHT2.abc',
        'SMARTLIGHT1.AA==',
        'x' * 16385,
      ]) {
        await expectLater(
          transfer.open(code, password),
          throwsA(isA<SetupTransferException>()),
        );
      }
      await expectLater(
        transfer.seal(ConnectionConfig([]), password),
        throwsA(isA<SetupTransferException>()),
      );
      await expectLater(
        transfer.seal(ConnectionConfig([tapoConfig()]), 'short'),
        throwsA(isA<SetupTransferException>()),
      );
    },
  );
  test('authenticated but invalid connection data is not accepted', () async {
    final fixture = jsonDecode(
      File('test/fixtures/setup_transfer.json').readAsStringSync(),
    ) as Map;
    for (final code in fixture['invalidCodes'] as List) {
      await expectLater(
        transfer.open(code, fixture['password']),
        throwsA(isA<SetupTransferException>()),
      );
    }
  });
}
