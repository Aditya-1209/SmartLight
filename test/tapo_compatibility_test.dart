import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/crypto_utils.dart';
import 'package:smart_light/services/local/tapo_aes.dart';
import 'package:smart_light/services/local/tapo_client.dart';

import 'support.dart';

List<int> unhex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

/// Simulates a legacy strip, including its RSA exchange and encrypted login.
class LegacyStrip {
  final key = List.generate(16, (i) => i);
  final iv = List.generate(16, (i) => 16 + i);
  late final cipher = TapoAesCipher(key, iv);
  int klapAttempts = 0, aesAttempts = 0, logins = 0, commands = 0;
  int loginError = 0, commandError = 0;
  int klapStatus = 404;
  bool on = true, invalidKey = false;
  String? cookie;

  http.Response jsonResponse(Object body, {Map<String, String>? headers}) =>
      http.Response(jsonEncode(body), 200, headers: headers ?? {});

  Future<http.Response> respond(http.Request request) async {
    try {
      return await _respond(request);
    } catch (error, stack) {
      // This fake server contains only the public fixture credentials.
      printOnFailure('$error\n$stack');
      rethrow;
    }
  }

  Future<http.Response> _respond(http.Request request) async {
    expect(request.url.host, tapoConfig().host);
    expect(request.followRedirects, false);
    expect(
      request.bodyBytes,
      isNot(containsAllInOrder(utf8.encode('test-password'))),
    );
    if (request.url.path == '/app/handshake1') {
      klapAttempts++;
      expect(request.headers.containsKey('Cookie'), false);
      return http.Response(
        klapStatus == 400 ? '' : 'not supported',
        klapStatus,
      );
    }
    expect(request.url.path, '/app');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    final body = jsonDecode(request.body) as Map;
    if (body['method'] == 'handshake') {
      aesAttempts++;
      expect(request.url.hasQuery, false);
      expect(request.headers.containsKey('Cookie'), false);
      final pem = (body['params'] as Map)['key'] as String;
      final der = base64Decode(
        pem
            .split('\n')
            .where((line) => line.isNotEmpty && !line.startsWith('-----'))
            .join(),
      );
      final spki = ASN1SubjectPublicKeyInfo.fromSequence(
        ASN1Parser(der).nextObject() as ASN1Sequence,
      );
      expect(
        spki.algorithm.algorithm.objectIdentifierAsString,
        '1.2.840.113549.1.1.1',
      );
      final rsa =
          ASN1Parser(bytes(spki.subjectPublicKey.stringValues!)).nextObject()
              as ASN1Sequence;
      final n = (rsa.elements![0] as ASN1Integer).integer!;
      final e = (rsa.elements![1] as ASN1Integer).integer!;
      expect(n.bitLength, 1024);
      expect(e, BigInt.from(65537));
      final encrypt = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(n, e)));
      cookie = 'TP_SESSIONID=aes-session-$aesAttempts';
      return jsonResponse(
        {
          'error_code': 0,
          'result': {
            'key': invalidKey
                ? base64Encode([1, 2])
                : base64Encode(encrypt.process(bytes([...key, ...iv]))),
          },
        },
        headers: {'set-cookie': '$cookie; Path=/; TIMEOUT=86400'},
      );
    }
    expect(body['method'], 'securePassthrough');
    expect(request.headers['Cookie'], cookie);
    final inner =
        cipher.decrypt((body['params'] as Map)['request'] as String) as Map;
    Map<String, dynamic> reply;
    if (inner['method'] == 'login_device') {
      logins++;
      expect(request.url.hasQuery, false);
      final params = inner['params'] as Map;
      expect(
        params['username'],
        'NTY3MTU5ZDYyMmZmYmI1MGIxMWIwZWZkMzA3YmUzNTg2MjRhMjZlZQ==',
      );
      expect(
        utf8.decode(base64Decode(params['password'] as String)),
        'test-password',
      );
      reply = {
        'error_code': loginError,
        'result': {'token': 'fake-token'},
      };
    } else {
      expect(request.url.queryParameters, {'token': 'fake-token'});
      if (inner['method'] == 'set_device_info') {
        commands++;
        if (commandError == 0) {
          on = (inner['params'] as Map)['device_on'] as bool;
        }
        reply = {'error_code': commandError};
      } else {
        expect(inner['method'], 'get_device_info');
        reply = {
          'error_code': 0,
          'result': {
            'device_on': on,
            'brightness': 60,
            'hue': 120,
            'saturation': 100,
            'color_temp': 0,
            'color_temp_range': [9000, 9000],
            'model': 'L920',
            'lighting_effect': {'enable': 0},
          },
        };
      }
    }
    return jsonResponse({
      'error_code': 0,
      'result': {'response': cipher.encrypt(reply)},
    });
  }
}

void main() {
  test('AES login encoding and encryption match independent Python vector', () {
    final vectors = jsonDecode(
      File('test/fixtures/protocol_vectors.json').readAsStringSync(),
    ) as Map;
    final v = vectors['tapo_aes'] as Map;
    final cipher = TapoAesCipher(
      unhex(v['key'] as String),
      unhex(v['iv'] as String),
    );
    final request = {
      'method': 'login_device',
      'params': TapoAesCipher.loginParams('test@example.com', 'test-password'),
      'requestTimeMils': 0,
    };
    expect(jsonEncode(request), v['clear']);
    expect(cipher.encrypt(request), v['encrypted']);
    expect(cipher.decrypt(v['encrypted'] as String), request);
  });

  for (final status in [200, 400, 403, 404, 405]) {
    test(
      'KLAP HTTP $status legacy response negotiates AES and reuses session',
      () async {
        final strip = LegacyStrip()..klapStatus = status;
        final client = TapoClient(
          tapoConfig(),
          clientFactory: () => MockClient(strip.respond),
        );
        addTearDown(client.dispose);
        final light = await client.read();
        expect(light.isOn, true);
        expect(light.supportsRgb, true);
        expect(light.supportsTemperature, false);
        await client.command(light, const LightCommand(on: false));
        expect((await client.read()).isOn, false);
        expect(strip.klapAttempts, 1);
        expect(strip.aesAttempts, 1);
        expect(strip.logins, 1);
        expect(strip.commands, 1);
      },
    );
  }

  test(
    'AES authentication rejection has cooldown and does not retry password',
    () async {
      final strip = LegacyStrip()..loginError = -1501;
      final client = TapoClient(
        tapoConfig(),
        clientFactory: () => MockClient(strip.respond),
      );
      addTearDown(client.dispose);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.read(),
          throwsA(
            isA<DeviceException>().having(
              (e) => e.kind,
              'kind',
              DeviceError.unauthorized,
            ),
          ),
        );
      }
      expect(strip.logins, 1);
      expect(strip.klapAttempts, 1);
    },
  );

  test('AES rejects invalid key before sending account credentials', () async {
    final strip = LegacyStrip()..invalidKey = true;
    final client = TapoClient(
      tapoConfig(),
      clientFactory: () => MockClient(strip.respond),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.read(),
      throwsA(
        isA<DeviceException>().having(
          (e) => e.kind,
          'kind',
          DeviceError.malformed,
        ),
      ),
    );
    expect(strip.logins, 0);
  });

  test(
    'Failed AES command is not replayed; next read creates a clean session',
    () async {
      final strip = LegacyStrip();
      final client = TapoClient(
        tapoConfig(),
        clientFactory: () => MockClient(strip.respond),
      );
      addTearDown(client.dispose);
      final light = await client.read();
      strip.commandError = 9999;
      await expectLater(
        client.command(light, const LightCommand(on: false)),
        throwsA(
          isA<DeviceException>().having(
            (e) => e.message,
            'message',
            contains('9999'),
          ),
        ),
      );
      expect(strip.commands, 1);
      expect((await client.read()).isOn, true);
      expect(strip.aesAttempts, 2);
    },
  );

  test('Unrecognized protocols report statuses and numeric codes, never device text', () async {
    var calls = 0;
    final client = TapoClient(
      tapoConfig(),
      clientFactory: () => MockClient((r) async {
        calls++;
        return r.url.path == '/app/handshake1'
            ? http.Response('test-password', 403)
            : http.Response(
                '{"error_code":1003,"msg":"fake-token test-password"}',
                200,
              );
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.read(),
      throwsA(
        isA<DeviceException>()
            .having((e) => e.kind, 'kind', DeviceError.unavailable)
            .having(
              (e) => e.message,
              'message',
              allOf(
                contains('KLAP: HTTP 403'),
                contains('AES: HTTP 200, code 1003'),
                isNot(contains('test-password')),
                isNot(contains('fake-token')),
              ),
            ),
      ),
    );
    expect(calls, 2);
  });

  for (final status in [301, 401, 429, 500, 503]) {
    test(
      'HTTP $status reports handshake status without trying AES or following redirect',
      () async {
        var calls = 0;
        final client = TapoClient(
          tapoConfig(),
          clientFactory: () => MockClient((r) async {
            calls++;
            expect(r.followRedirects, false);
            return http.Response(
              'test-password',
              status,
              headers: {'location': 'https://example.com'},
            );
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.read(),
          throwsA(
            isA<DeviceException>().having(
              (e) => e.message,
              'message',
              allOf(contains('HTTP $status'), isNot(contains('test-password'))),
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }
}
