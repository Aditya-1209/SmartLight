import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_timer.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/demo_lights.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/crypto_utils.dart';
import 'package:smart_light/services/local/tapo_client.dart';
import 'package:smart_light/services/local/tuya_client.dart';
import 'package:smart_light/services/local/tuya_protocol.dart';

import 'support.dart';

DeviceConnection tube({TuyaProfile profile = TuyaProfile.modern}) =>
    DeviceConnection(
      slotId: 'tube1',
      name: 'Tube',
      brand: DeviceBrand.tuya,
      host: '192.168.1.2',
      deviceId: 'fake-device',
      localKey: '0123456789abcdef',
      profile: profile,
    );

class TimerTransport extends TuyaTransport {
  TimerTransport() : super(tube());
  Map<String, dynamic> status = {'20': true, '26': 0};
  final writes = <Map<String, dynamic>>[];
  bool ignoreWrite = false, loseAcknowledgement = false;
  @override
  Future<Map<String, dynamic>> exchange({Map<String, dynamic>? dps}) async {
    if (dps != null) {
      writes.add(Map.of(dps));
      if (!ignoreWrite) status.addAll(dps);
      if (loseAcknowledgement) {
        throw const DeviceException(DeviceError.timeout, 'Lost reply');
      }
      return {};
    }
    return Map.of(status);
  }
}

/// Fixture credentials only. The simulated light stores its own timer between
/// client sessions, like a device does when the app is closed.
class TimerStrip {
  List<Map<String, dynamic>> rules = [];
  final calls = <String>[];
  Map? lastAdd;
  bool ignoreWrite = false, loseAcknowledgement = false;
  int errorCode = 0;
  TapoClient client() {
    final config = tapoConfig();
    final auth = sha256([
      ...sha1(utf8.encode(config.email)),
      ...sha1(utf8.encode(config.password)),
    ]);
    final remote = List.generate(16, (i) => i + 16);
    KlapCipher? cipher;
    return TapoClient(
      config,
      clientFactory: () => MockClient((request) async {
        if (request.url.path == '/app/handshake1') {
          final local = request.bodyBytes;
          cipher = KlapCipher(local, remote, auth);
          return http.Response.bytes(
            [
              ...remote,
              ...sha256([...local, ...remote, ...auth]),
            ],
            200,
            headers: {'set-cookie': 'TP_SESSIONID=timer-fixture;TIMEOUT=86400'},
          );
        }
        if (request.url.path == '/app/handshake2') {
          return http.Response('', 200);
        }
        final seq = int.parse(request.url.queryParameters['seq']!);
        cipher!.sequence = seq;
        final data =
            jsonDecode(utf8.decode(cipher!.decrypt(request.bodyBytes))) as Map;
        final method = data['method'] as String;
        calls.add(method);
        Object result = {};
        if (method == 'get_countdown_rules') result = {'rule_list': rules};
        if (method == 'remove_countdown_rules' && !ignoreWrite) {
          expect(data['params'], {'remove_all': true});
          rules = [];
        }
        if (method == 'add_countdown_rule') {
          lastAdd = data['params'] as Map;
          if (!ignoreWrite) {
            rules = [
              {
                'id': 'device-timer-1',
                ...Map<String, dynamic>.from(lastAdd!),
                'remain': lastAdd!['delay'],
              },
            ];
          }
          if (loseAcknowledgement) {
            throw const DeviceException(DeviceError.timeout, 'Lost reply');
          }
          result = {'id': 'device-timer-1'};
        }
        cipher!.sequence = seq - 1;
        return http.Response.bytes(
          cipher!.encrypt(
            utf8.encode(
              jsonEncode({'error_code': errorCode, 'result': result}),
            ),
          ),
          200,
        );
      }),
    );
  }
}

void main() {
  test(
    'countdown validates boundaries and clock time crosses midnight/year',
    () {
      final now = DateTime(2026, 12, 31, 23, 59, 30);
      expect(nextTimerTime(now, 0, 15), DateTime(2027, 1, 1, 0, 15));
      expect(nextTimerTime(now, 23, 59), DateTime(2027, 1, 1, 23, 59));
      expect(
        countdownSeconds(now.add(const Duration(days: 1)), now: now),
        86400,
      );
      for (final duration in [
        const Duration(milliseconds: 999),
        const Duration(days: 1, seconds: 1),
        const Duration(seconds: -1),
      ]) {
        expect(
          () => countdownSeconds(now.add(duration), now: now),
          throwsA(isA<DeviceException>()),
        );
      }
    },
  );

  test(
    'Tuya writes only countdown, confirms it, sees it on reopen and cancels',
    () async {
      final transport = TimerTransport();
      final client = TuyaClient(tube(), transport: transport);
      addTearDown(client.dispose);
      final target = DateTime.now().add(const Duration(minutes: 30));
      final status = await client.setTimer(target, on: false);
      expect(status.active!.on, false);
      expect(transport.writes.single.keys, ['26']);
      expect(transport.writes.single['26'], inInclusiveRange(1798, 1800));
      final reopened = TuyaClient(tube(), transport: transport);
      expect((await reopened.readTimer()).active, isNotNull);
      expect((await reopened.cancelTimer()).active, isNull);
      expect(transport.writes.last, {'26': 0});
      expect(transport.status['20'], true);
    },
  );

  test(
    'Tuya requires opposite power and refuses to overwrite active timers',
    () async {
      final transport = TimerTransport();
      final client = TuyaClient(tube(), transport: transport);
      final target = DateTime.now().add(const Duration(minutes: 10));
      await expectLater(
        client.setTimer(target, on: true),
        throwsA(isA<DeviceException>()),
      );
      expect(transport.writes, isEmpty);
      transport.status['26'] = 60;
      await expectLater(
        client.setTimer(target, on: false),
        throwsA(isA<DeviceException>()),
      );
      expect(transport.writes, isEmpty);
      transport.status = {'20': false, '26': 0};
      expect((await client.setTimer(target, on: true)).active!.on, true);
    },
  );

  test(
    'Tuya never guesses unsupported/malformed DP or legacy mapping',
    () async {
      for (final value in [null, '0', -1, 86401]) {
        final transport = TimerTransport()..status = {'20': true, '26': ?value};
        final client = TuyaClient(tube(), transport: transport);
        expect((await client.readTimer()).supported, false);
        await expectLater(
          client.setTimer(
            DateTime.now().add(const Duration(minutes: 2)),
            on: false,
          ),
          throwsA(isA<DeviceException>()),
        );
        await expectLater(
          client.cancelTimer(),
          throwsA(isA<DeviceException>()),
        );
        expect(transport.writes, isEmpty);
      }
      final transport = TimerTransport()..status = {'1': true, '26': 0};
      expect(
        (await TuyaClient(
          tube(profile: TuyaProfile.legacy),
          transport: transport,
        ).readTimer()).supported,
        false,
      );
    },
  );

  test(
    'Tuya uncertain or ignored writes never report success or replay',
    () async {
      for (final lost in [true, false]) {
        final transport = TimerTransport()
          ..loseAcknowledgement = lost
          ..ignoreWrite = !lost;
        final client = TuyaClient(tube(), transport: transport);
        await expectLater(
          client.setTimer(
            DateTime.now().add(const Duration(minutes: 2)),
            on: false,
          ),
          throwsA(same(timerUnconfirmed)),
        );
        expect(transport.writes, hasLength(1));
      }
    },
  );

  test('Tapo native timer encrypted payload, persistence across sessions and cancel', () async {
    final strip = TimerStrip();
    final client = strip.client();
    final result = await client.setTimer(
      DateTime.now().add(const Duration(hours: 1)),
      on: false,
    );
    expect(strip.lastAdd!['desired_states'], {'on': false});
    expect(strip.lastAdd!['enable'], true);
    expect(strip.lastAdd!['delay'], inInclusiveRange(3598, 3600));
    expect(result.active!.id, 'device-timer-1');
    client.dispose();
    final reopened = strip.client();
    addTearDown(reopened.dispose);
    expect((await reopened.readTimer()).active!.on, false);
    expect((await reopened.cancelTimer()).active, isNull);
  });

  test('Tapo reads legacy action, blocks existing/unknown/multiple timers without writes', () async {
    final strip = TimerStrip()
      ..rules = [
        {'id': 'vendor', 'delay': 60, 'remain': 40, 'action': 'off'},
      ];
    final client = strip.client();
    addTearDown(client.dispose);
    expect((await client.readTimer()).active!.on, false);
    await expectLater(
      client.setTimer(
        DateTime.now().add(const Duration(minutes: 2)),
        on: false,
      ),
      throwsA(isA<DeviceException>()),
    );
    expect(strip.calls.toSet(), {'get_countdown_rules'});
    strip.rules.single.remove('action');
    await expectLater(client.readTimer(), throwsA(isA<DeviceException>()));
    strip.rules = [
      {...strip.rules.single},
      {...strip.rules.single},
    ];
    await expectLater(client.readTimer(), throwsA(isA<DeviceException>()));
    expect(strip.calls.toSet(), {'get_countdown_rules'});
  });

  test(
    'Tapo inactive timer cleanup and unconfirmed writes do not replay',
    () async {
      final strip = TimerStrip()
        ..rules = [
          {'id': 'expired', 'remain': 0},
        ];
      final client = strip.client();
      addTearDown(client.dispose);
      expect((await client.readTimer()).active, isNull);
      strip.loseAcknowledgement = true;
      await expectLater(
        client.setTimer(
          DateTime.now().add(const Duration(minutes: 2)),
          on: true,
        ),
        throwsA(same(timerUnconfirmed)),
      );
      expect(strip.calls.where((c) => c == 'add_countdown_rule'), hasLength(1));
      expect((await client.readTimer()).active!.on, true);
      strip.ignoreWrite = true;
      await expectLater(client.cancelTimer(), throwsA(same(timerUnconfirmed)));
    },
  );

  test('room timers report partial failure and preserve saved data', () async {
    final backend = DemoLights(latency: Duration.zero)
      ..failCommands.add('light.wipro_tube_2');
    final settings = MemorySettings(
      const AppSettings(
        demo: true,
        customScenes: [
          LightScene('custom-bedtime', 'Bedtime', 'Keep this scene', {
            'tube1': LightCommand(brightnessPercent: 20),
          }),
        ],
      ),
    );
    final savedSettings = settings.value;
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final container = testContainer(
      backend: backend,
      credentials: credentials,
      settings: settings,
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    final previous = container.read(appControllerProvider).config;
    final report = await controller.scheduleTimers(
      {'tube1', 'tube2', 'strip'},
      DateTime.now().add(const Duration(minutes: 30)),
      on: false,
    );
    expect(report.succeeded, hasLength(2));
    expect(report.failed.keys, ['Wipro Tube 2']);
    expect(container.read(appControllerProvider).busy, isEmpty);
    expect(credentials.config, same(previous));
    expect(settings.value, same(savedSettings));
    expect(settings.value.customScenes.single.name, 'Bedtime');
    expect((await controller.readTimer('tube1')).active, isNotNull);
    expect((await controller.cancelLightTimer('tube1')).hasFailures, false);
    expect((await controller.readTimer('tube1')).active, isNull);
  });
}
