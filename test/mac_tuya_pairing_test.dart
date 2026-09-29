import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/services/local/crypto_utils.dart' as crypto;
import 'package:smart_light/services/local/tuya_protocol.dart';
import 'package:smart_light/services/pairing/desktop_tuya_pairing.dart';
import 'package:smart_light/services/pairing/tuya_cloud_setup.dart';
import 'package:smart_light/services/pairing/tuya_discovery.dart';
import 'package:smart_light/services/pairing/tuya_smart_link.dart';

const config = TuyaCloudConfig(
  clientId: 'testclientid1234',
  secret: 'test-secret-value',
  schema: 'testschema',
);

class FakeApi extends TuyaCloudSetup {
  FakeApi() : super(config);
  bool rejectToken = false;
  final usernames = <String>[];
  final calls = <String>[];
  Completer<void>? userPending;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    calls.add(path);
    if (path.endsWith('/user')) {
      usernames.add(body!['username'] as String);
      await userPending?.future;
      return {'uid': 'fake-user'};
    }
    if (path.endsWith('/token')) {
      if (rejectToken) throw const TuyaSetupException('denied');
      return {'token': '12345678', 'secret': 'abcd', 'region': 'EU'};
    }
    if (path.endsWith('/devices')) return <Map>[];
    return <String, dynamic>{};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cloud signatures match independent Python HMAC fixtures', () {
    for (final entry in {
      '': 'A3CCA049895400802384981D93F6BA3940A44436B0A2D97C915F3410F61E5CF0',
      'synthetic-session':
          '038E9A4F3627B3D475A80F4C8D057BFF4682538AA10DE6163383364A31056CC4',
    }.entries) {
      expect(
        TuyaCloudSetup.signature(
          clientId: 'test-client-id',
          secret: 'test-secret-value',
          timestamp: '1700000000000',
          method: 'POST',
          path: '/v1.0/device/paring/token',
          body: '{"uid":"fake-user"}',
          token: entry.key,
        ),
        entry.value,
      );
    }
  });
  test(
    'cloud authenticates, caches token, signs exact body and refuses redirects',
    () async {
      final requests = <http.Request>[];
      final api = TuyaCloudSetup(
        config,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.host, TuyaCloudConfig.host);
          expect(request.followRedirects, isFalse);
          if (request.url.path == '/v1.0/token') {
            expect(request.headers.containsKey('access_token'), isFalse);
            return http.Response(
              jsonEncode({
                'success': true,
                'result': {'access_token': 'fake-token', 'expire_time': 7200},
              }),
              200,
            );
          }
          expect(request.headers['access_token'], 'fake-token');
          expect(request.body, '{"uid":"fake-user"}');
          return http.Response('{"success":true,"result":{}}', 200);
        }),
      );
      for (var i = 0; i < 2; i++) {
        await api.request(
          'POST',
          '/v1.0/device/paring/token',
          body: {'uid': 'fake-user'},
        );
      }
      expect(requests.where((r) => r.url.path == '/v1.0/token').length, 1);
      api.close();
      await expectLater(
        api.request('GET', '/v1.0/apps/testschema'),
        throwsA(isA<TuyaSetupException>()),
      );
    },
  );
  test('vendor errors cannot leak secrets into setup messages', () async {
    final api = TuyaCloudSetup(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'code': 1106,
            'msg': 'leaked ${config.secret}',
          }),
          200,
        ),
      ),
    );
    await expectLater(
      api.request('GET', '/v1.0/apps/testschema'),
      throwsA(
        isA<TuyaSetupException>().having(
          (e) => e.message,
          'safe error',
          allOf(contains('1106'), isNot(contains(config.secret))),
        ),
      ),
    );
    api.close();
  });
  test('EZ byte lengths match upstream encoder including UTF-8 Wi-Fi', () {
    final fixtures = jsonDecode(
      File('test/fixtures/tuya_smart_link.json').readAsStringSync(),
    ) as List;
    for (final fixture in fixtures) {
      final input = fixture['input'] as Map;
      expect(
        TuyaSmartLink.encode(
          ssid: input['ssid'],
          password: input['wifiPassword'],
          region: input['region'],
          token: input['token'],
          secret: input['secret'],
        ),
        fixture['output'],
      );
    }
    expect(
      () => TuyaSmartLink.encode(
        ssid: '💡' * 9,
        password: '',
        region: 'EU',
        token: '12345678',
        secret: 'abcd',
      ),
      throwsA(isA<TuyaSetupException>()),
    );
  });
  test('discovery verifies integrity and uses private sender instead of payload IP', () {
    final key = crypto.md5(ascii.encode('yGAdlopoPVldABfn'));
    final packet = TuyaCodec(TuyaVersion.v35, key).encode(
      1,
      0x23,
      utf8.encode('{"gwId":"test-light","ip":"8.8.8.8","version":"3.5"}'),
      returnCode: 0,
      nonce: List.filled(12, 1),
    );
    expect(TuyaDiscovery.decode(packet, '192.168.1.50'), {
      'deviceId': 'test-light',
      'host': '192.168.1.50',
      'version': '3.5',
    });
    expect(TuyaDiscovery.decode(packet, '8.8.8.8'), isNull);
    packet[32] ^= 1;
    expect(TuyaDiscovery.decode(packet, '192.168.1.50'), isNull);
  });
  test(
    'setup verifies app first and reuses its profile after failed token check',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi()..rejectToken = true;
      final pairing = DesktopTuyaPairing(apiFactory: (_) => api);
      await expectLater(
        pairing.prepare(config),
        throwsA(isA<TuyaSetupException>()),
      );
      api.rejectToken = false;
      expect(await pairing.prepare(config), isEmpty);
      expect(api.calls.first, '/v1.0/apps/testschema');
      expect(api.usernames.length, 1);
      expect((await pairing.savedConfig())?.schema, 'testschema');
      pairing.close();
    },
  );
  test(
    'cancelling while registering cannot issue a later pairing token',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi()..userPending = Completer<void>();
      final pairing = DesktopTuyaPairing(apiFactory: (_) => api);
      final result = expectLater(
        pairing.prepare(config),
        throwsA(isA<TuyaSetupException>()),
      );
      for (var i = 0; i < 20 && api.usernames.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(api.usernames, hasLength(1));
      pairing.cancel();
      api.userPending!.complete();
      await result;
      expect(api.calls.any((p) => p.endsWith('/token')), isFalse);
      pairing.close();
    },
  );
}
