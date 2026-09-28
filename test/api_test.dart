import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/services/ha_exception.dart';
import 'package:smart_light/services/home_assistant_api.dart';

void main() {
  final config = ConnectionConfig('http://localhost:8123', 'test-token');
  final lightJson = <String, dynamic>{
    'entity_id': 'light.test',
    'state': 'on',
    'attributes': {
      'brightness': 150,
      'supported_color_modes': ['rgb', 'color_temp'],
      'min_color_temp_kelvin': 2200,
      'max_color_temp_kelvin': 6500,
    },
  };
  HomeAssistantApi api(
    Future<http.Response> Function(http.Request) handle, {
    Duration timeout = const Duration(seconds: 1),
  }) {
    final value = HomeAssistantApi(
      config,
      client: MockClient(handle),
      timeout: timeout,
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'successful connection uses bearer header and correct endpoint',
    () async {
      await api((request) async {
        expect(request.url.path, '/api/');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.followRedirects, false);
        return http.Response('{"message":"API running."}', 200);
      }).testConnection();
    },
  );
  for (final code in [401, 403, 500, 503, 302]) {
    test('HTTP $code becomes a typed, sanitized failure', () async {
      await expectLater(
        api((_) async => http.Response('sensitive body', code))
            .testConnection(),
        throwsA(
          isA<HaException>()
              .having(
                (e) => e.kind,
                'kind',
                code == 401 || code == 403
                    ? HaError.unauthorized
                    : code == 302
                    ? HaError.invalidUrl
                    : HaError.server,
              )
              .having(
                (e) => e.message.contains('sensitive'),
                'no response leak',
                false,
              ),
        ),
      );
    });
  }
  test('timeout is distinguished from offline', () async {
    await expectLater(
      api(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 5),
      ).testConnection(),
      throwsA(
        isA<HaException>().having((e) => e.kind, 'kind', HaError.timeout),
      ),
    );
    await expectLater(
      api((_) async => throw const SocketException('offline')).testConnection(),
      throwsA(
        isA<HaException>().having((e) => e.kind, 'kind', HaError.unreachable),
      ),
    );
    await expectLater(
      api((_) async => throw http.ClientException('network')).testConnection(),
      throwsA(
        isA<HaException>().having((e) => e.kind, 'kind', HaError.unreachable),
      ),
    );
  });
  test('malformed API response and state list fail safely', () async {
    for (final body in ['broken json', '[]', '{"hello":"world"}']) {
      await expectLater(
        api((_) async => http.Response(body, 200)).testConnection(),
        throwsA(isA<HaException>()),
      );
    }
    await expectLater(
      api((_) async => http.Response('{}', 200)).getLights(),
      throwsA(isA<HaException>()),
    );
  });
  test(
    'GET states filters nonlights and tolerates malformed entries',
    () async {
      final lights = await api((request) async {
        expect(request.url.path, '/api/states');
        return http.Response(
          jsonEncode([
            lightJson,
            {'entity_id': 'sensor.room'},
            null,
            5,
            {'entity_id': 'light.malformed', 'attributes': []},
          ]),
          200,
        );
      }).getLights();
      expect(lights.map((e) => e.entityId), ['light.test', 'light.malformed']);
    },
  );
  test('GET individual state verifies identity', () async {
    final light = await api((r) async {
      expect(r.url.path, '/api/states/light.test');
      return http.Response(jsonEncode(lightJson), 200);
    }).getLight('light.test');
    expect(light.isOn, true);
    await expectLater(
      api((_) async => http.Response(jsonEncode(lightJson), 200))
          .getLight('light.wrong'),
      throwsA(isA<HaException>()),
    );
  });
  final cases = <String, (LightCommand, Map<String, dynamic>)>{
    'on': (const LightCommand(), {'entity_id': 'light.test'}),
    'off': (const LightCommand(on: false), {'entity_id': 'light.test'}),
    'brightness': (
      const LightCommand(brightnessPercent: 50),
      {'entity_id': 'light.test', 'brightness': 128},
    ),
    'rgb': (
      const LightCommand(rgb: RgbColor(255, 0, 0)),
      {
        'entity_id': 'light.test',
        'rgb_color': [255, 0, 0],
        'brightness': 150,
      },
    ),
    'temperature': (
      const LightCommand(kelvin: 4000),
      {'entity_id': 'light.test', 'color_temp_kelvin': 4000, 'brightness': 150},
    ),
  };
  for (final entry in cases.entries) {
    test('service serialization ${entry.key}', () async {
      await api((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/services/light/${entry.value.$1.service}',
        );
        expect(jsonDecode(request.body), entry.value.$2);
        return http.Response('[]', 200);
      }).command(LightEntity.fromJson(lightJson), entry.value.$1);
    });
  }
}
