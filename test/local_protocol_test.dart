import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/crypto_utils.dart';
import 'package:smart_light/services/local/tapo_client.dart';
import 'package:smart_light/services/local/tuya_client.dart';
import 'package:smart_light/services/local/tuya_protocol.dart';

import 'support.dart';

List<int> unhex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
String hex(List<int> value) =>
    value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
DeviceConnection tuyaConfig({
  TuyaVersion version = TuyaVersion.v33,
  TuyaProfile profile = TuyaProfile.modern,
}) => DeviceConnection(
  slotId: 'tube1',
  name: 'Tube',
  brand: DeviceBrand.tuya,
  host: '192.168.1.2',
  deviceId: 'test-device',
  localKey: '0123456789abcdef',
  version: version,
  profile: profile,
);

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/protocol_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final key = utf8.encode(vectors['key'] as String),
      payload = utf8.encode(vectors['payload'] as String);
  test('KLAP matches independent Python encryption, verifies signature', () {
    final v = vectors['klap'] as Map;
    final cipher = KlapCipher(
      unhex(v['local'] as String),
      unhex(v['remote'] as String),
      unhex(v['auth'] as String),
    );
    final encoded = cipher.encrypt(utf8.encode(v['clear'] as String));
    expect(cipher.sequence, v['sequence']);
    expect(hex(encoded), v['packet']);
    expect(utf8.decode(cipher.decrypt(encoded)), v['clear']);
    encoded[0] ^= 1;
    expect(() => cipher.decrypt(encoded), throwsFormatException);
  });
  for (final version in TuyaVersion.values) {
    test('Tuya ${version.name} interoperates with TinyTuya golden frames', () {
      final codec = TuyaCodec(version, key);
      final expected = unhex(
        vectors[DeviceConnection.versionText(version)] as String,
      );
      final packet = codec.encode(
        7,
        8,
        payload,
        withVersion: true,
        returnCode: 0,
        nonce: ascii.encode('abcdefghijkl'),
      );
      expect(packet, expected);
      expect(codec.decode(expected).payload, payload);
      final corrupted = List<int>.from(expected)..[expected.length - 6] ^= 1;
      expect(() => codec.decode(corrupted), throwsA(anything));
    });
    test(
      'Tuya ${version.name} handles fragmented/coalesced frames and rejects lengths',
      () async {
        final frame = unhex(
          vectors[DeviceConnection.versionText(version)] as String,
        );
        final parsed = await tuyaFrames(
          Stream.fromIterable([
            frame.sublist(0, 3),
            frame.sublist(3, 17),
            [...frame.sublist(17), ...frame],
          ]),
          version,
        ).toList();
        expect(parsed, [frame, frame]);
        final oversized = List<int>.from(frame);
        oversized.setRange(
          version == TuyaVersion.v35 ? 14 : 12,
          version == TuyaVersion.v35 ? 18 : 16,
          u32(999999),
        );
        await expectLater(
          tuyaFrames(Stream.value(oversized), version),
          emitsError(isA<FormatException>()),
        );
      },
    );
    test(
      'Tuya ${version.name} TCP handshake, read and command on simulated light',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final config = tuyaConfig(version: version);
        final dps = <String, dynamic>{
          '20': true,
          '21': 'white',
          '22': 500,
          '23': 500,
          '24': '000003e803e8',
        };
        final handlers = <Future<void>>[];
        final failures = <Object>[];
        var queries = 0, changes = 0;
        server.listen((socket) {
          handlers.add(() async {
            final codec = TuyaCodec(version, key);
            final remote = List.generate(16, (i) => 16 + i);
            List<int>? local;
            try {
              await for (final packet in tuyaFrames(socket, version)) {
                final frame = codec.decode(packet, response: false);
                if (frame.command == 3) {
                  local = frame.payload;
                  socket.add(
                    codec.encode(1, 4, [
                      ...remote,
                      ...hmac256(key, local),
                    ], returnCode: 0),
                  );
                } else if (frame.command == 5) {
                  expect(frame.payload, hmac256(key, remote));
                  final mixed = List.generate(16, (i) => local![i] ^ remote[i]);
                  codec.key = version == TuyaVersion.v35
                      ? aesGcm(mixed, key, local!.sublist(0, 12)).sublist(0, 16)
                      : aesBlock(mixed, key, padding: false);
                } else if (frame.command == 10 || frame.command == 16) {
                  queries++;
                  socket.add(
                    codec.encode(
                      22,
                      frame.command,
                      utf8.encode(jsonEncode({'dps': dps})),
                      withVersion: true,
                      returnCode: 0,
                    ),
                  );
                } else {
                  final request = jsonDecode(utf8.decode(frame.payload)) as Map;
                  final data = version == TuyaVersion.v33
                      ? request
                      : request['data'] as Map;
                  dps.addAll(Map<String, dynamic>.from(data['dps'] as Map));
                  changes++;
                  socket.add(
                    codec.encode(23, frame.command, [], returnCode: 0),
                  );
                }
              }
            } catch (error) {
              failures.add(error);
            } finally {
              socket.destroy();
            }
          }());
        });
        final transport = TuyaTransport(
          config,
          connector: (_, _) =>
              Socket.connect(InternetAddress.loopbackIPv4, server.port),
        );
        final client = TuyaClient(config, transport: transport);
        addTearDown(client.dispose);
        final light = await client.read();
        expect(light.isOn, true);
        expect(light.brightnessPercent, 50);
        await client.command(light, const LightCommand(on: false));
        expect((await client.read()).isOn, false);
        expect(queries, 2);
        expect(changes, 1);
        client.dispose();
        await Future.wait(handlers);
        expect(failures, isEmpty);
      },
    );
  }
  test(
    'Tuya modern color brightness updates HSV instead of white brightness',
    () {
      final mapper = TuyaLightMapper(tuyaConfig());
      final light = mapper.parse({
        '20': true,
        '21': 'colour',
        '22': 900,
        '23': 500,
        '24': '00f003e801f4',
      });
      expect(light.brightnessPercent, 50);
      final update = mapper.commandData(
        light,
        const LightCommand(brightnessPercent: 25),
      );
      expect(update['24'], '00f003e800fa');
      expect(update.containsKey('22'), false);
      expect(
        mapper.commandData(light, const LightCommand(kelvin: 6500))['23'],
        1000,
      );
      expect(
        mapper.commandData(light, const LightCommand(brightnessPercent: 0)),
        {'20': false},
      );
    },
  );
  test('Tuya legacy profile and unsupported data remain conservative', () {
    final mapper = TuyaLightMapper(tuyaConfig(profile: TuyaProfile.legacy));
    final light = mapper.parse({
      '1': true,
      '2': 'white',
      '3': 255,
      '4': 0,
      '5': 'ff00000000ffff',
    });
    expect(light.colorTempKelvin, 2700);
    expect(
      mapper.commandData(
        light,
        const LightCommand(rgb: RgbColor(255, 0, 0)),
      )['5'],
      'ff00000000ffff',
    );
    expect(mapper.parse({'1': false}).supportsRgb, false);
    expect(() => mapper.parse({'20': true}), throwsA(isA<DeviceException>()));
  });
  for (final legacy in [false, true]) {
    test(
      'Tapo KLAP ${legacy ? 'v1' : 'v2'} connection, capabilities, cookie and power',
      () async {
        final config = tapoConfig();
        final auth = legacy
            ? md5(
                ascii.encode(
                  '${hex(md5(utf8.encode(config.email)))}${hex(md5(utf8.encode(config.password)))}',
                ),
              )
            : sha256([
                ...sha1(utf8.encode(config.email)),
                ...sha1(utf8.encode(config.password)),
              ]);
        final remote = List.generate(16, (i) => 16 + i);
        KlapCipher? serverCipher;
        List<int>? local;
        var on = true;
        var range = [2500, 6500];
        var handshakes = 0;
        final client = TapoClient(
          config,
          clientFactory: () => MockClient((request) async {
            expect(request.url.host, config.host);
            expect(request.followRedirects, false);
            expect(
              request.bodyBytes,
              isNot(containsAllInOrder(utf8.encode(config.password))),
            );
            if (request.url.path == '/app/handshake1') {
              handshakes++;
              local = request.bodyBytes;
              serverCipher = KlapCipher(local!, remote, auth);
              return http.Response.bytes(
                [
                  ...remote,
                  ...sha256([...local!, if (!legacy) ...remote, ...auth]),
                ],
                200,
                headers: {
                  'set-cookie': 'TP_SESSIONID=test-session;TIMEOUT=86400',
                },
              );
            }
            expect(request.headers['Cookie'], 'TP_SESSIONID=test-session');
            if (request.url.path == '/app/handshake2') {
              expect(
                request.bodyBytes,
                sha256([...remote, if (!legacy) ...local!, ...auth]),
              );
              return http.Response('', 200);
            }
            final seq = int.parse(request.url.queryParameters['seq']!);
            serverCipher!.sequence = seq;
            final data = jsonDecode(
              utf8.decode(serverCipher!.decrypt(request.bodyBytes)),
            ) as Map;
            if (data['method'] == 'set_device_info') {
              on = (data['params'] as Map)['device_on'] as bool;
            }
            final response = {
              'error_code': 0,
              'result': data['method'] == 'get_device_info'
                  ? {
                      'device_on': on,
                      'brightness': 60,
                      'hue': 120,
                      'saturation': 100,
                      'color_temp': 0,
                      'color_temp_range': range,
                      'lighting_effect': {'enable': 0},
                    }
                  : {},
            };
            serverCipher!.sequence = seq - 1;
            return http.Response.bytes(
              serverCipher!.encrypt(utf8.encode(jsonEncode(response))),
              200,
            );
          }),
        );
        addTearDown(client.dispose);
        final light = await client.read();
        expect(light.supportsTemperature, true);
        expect(light.supportsRgb, true);
        expect(
          TapoClient.commandData(
            light,
            const LightCommand(rgb: RgbColor(255, 0, 0)),
          )['lighting_effect'],
          {'enable': 0},
        );
        await client.command(light, const LightCommand(on: false));
        expect((await client.read()).isOn, false);
        range = [9000, 9000];
        expect((await client.read()).supportsTemperature, false);
        expect(handshakes, 1);
      },
    );
  }
  test('Tuya session derivation matches independent reference', () {
    final local = List.generate(16, (i) => i),
        remote = List.generate(16, (i) => 16 + i);
    final mixed = List.generate(16, (i) => local[i] ^ remote[i]);
    expect(hex(aesBlock(mixed, key, padding: false)), vectors['session34']);
    expect(
      hex(aesGcm(mixed, key, local.sublist(0, 12)).sublist(0, 16)),
      vectors['session35'],
    );
  });
  test(
    'Tapo refuses invalid credentials and rate limits repeated logins',
    () async {
      var attempts = 0;
      final client = TapoClient(
        tapoConfig(),
        clientFactory: () => MockClient((_) async {
          attempts++;
          return http.Response.bytes(List.filled(48, 1), 200);
        }),
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
      expect(attempts, 1);
    },
  );
  test('Tapo unreachable and timeout errors contain no credentials', () async {
    final client = TapoClient(
      tapoConfig(),
      clientFactory: () =>
          MockClient((_) async => throw TimeoutException('test-password')),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.read(),
      throwsA(
        isA<DeviceException>()
            .having((e) => e.kind, 'kind', DeviceError.timeout)
            .having(
              (e) => e.message,
              'message',
              isNot(contains('test-password')),
            ),
      ),
    );
  });
}
