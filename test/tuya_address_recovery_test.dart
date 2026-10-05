import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/light_timer.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/lights_repository.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/auto_tuya_client.dart';
import 'package:smart_light/services/local/crypto_utils.dart';
import 'package:smart_light/services/local/device_client.dart';
import 'package:smart_light/services/local/device_timer_client.dart';
import 'package:smart_light/services/local/resolved_connection.dart';
import 'package:smart_light/services/local/tuya_client.dart';
import 'package:smart_light/services/local/tuya_lan_discovery.dart';
import 'package:smart_light/services/local/tuya_protocol.dart';
import 'package:smart_light/services/pairing/tuya_discovery.dart';

import 'support.dart';

const oldHost = '192.168.1.25', newHost = '192.168.1.75';
const offline = DeviceException(DeviceError.unreachable, 'Offline');
DeviceConnection tube({
  String slot = 'tube1',
  String host = oldHost,
  TuyaVersion version = TuyaVersion.v33,
}) => DeviceConnection(
  slotId: slot,
  name: slot,
  brand: DeviceBrand.tuya,
  host: host,
  deviceId: 'synthetic-$slot',
  localKey: '0123456789abcdef',
  version: version,
);
TuyaDiscoveredLight hint({String host = newHost, String slot = 'tube1'}) =>
    TuyaDiscoveredLight(deviceId: 'synthetic-$slot', host: host);

class FakeTube implements DeviceClient, DeviceTimerClient {
  FakeTube(this.config, {this.readError, this.commandError, this.pending});
  final DeviceConnection config;
  final Object? readError, commandError;
  final Completer<void>? pending;
  int commands = 0, timerWrites = 0, timerCancels = 0;
  bool disposed = false;
  @override
  Future<LightEntity> read() async {
    await pending?.future;
    if (readError != null) throw readError!;
    return LightEntity(
      entityId: config.entityId,
      friendlyName: config.name,
      state: 'on',
      attributes: {'brightness': 120},
    );
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) async {
    commands++;
    if (commandError != null) throw commandError!;
  }

  @override
  Future<LightTimerStatus> readTimer() async =>
      const LightTimerStatus(isOn: true);
  @override
  Future<LightTimerStatus> setTimer(DateTime endsAt, {required bool on}) async {
    timerWrites++;
    return LightTimerStatus(
      isOn: true,
      active: LightTimer(id: 'countdown', endsAt: endsAt, on: on),
    );
  }

  @override
  Future<LightTimerStatus> cancelTimer() async {
    timerCancels++;
    return const LightTimerStatus(isOn: true);
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final udpKey = md5(ascii.encode('yGAdlopoPVldABfn'));
  final json = utf8.encode(
    '{"gwId":"synthetic-tube1","ip":"8.8.8.8","version":"3.3"}',
  );

  test(
    'UDP plaintext, ECB and GCM identify ID using sender, not advertised IP',
    () {
      List<int> framed(List<int> body, {bool retcode = true}) {
        final payload = [if (retcode) ...u32(0), ...body];
        final signed = [
          ...u32(0x55aa),
          ...u32(1),
          ...u32(0x23),
          ...u32(payload.length + 8),
          ...payload,
        ];
        return [...signed, ...u32(crc32(signed)), ...u32(0xaa55)];
      }

      final packets = [
        framed(json),
        framed(json, retcode: false),
        framed(aesBlock(json, udpKey)),
        aesBlock(json, udpKey),
        TuyaCodec(TuyaVersion.v35, udpKey).encode(1, 0x23, json, returnCode: 0),
      ];
      for (final packet in packets) {
        expect(TuyaDiscovery.decode(packet, newHost), {
          'deviceId': 'synthetic-tube1',
          'host': newHost,
          'version': '3.3',
        });
        expect(TuyaDiscovery.decode(packet, '8.8.8.8'), isNull);
      }
      final corrupt = framed(json)..[22] ^= 1;
      expect(TuyaDiscovery.decode(corrupt, newHost), isNull);
      expect(TuyaDiscovery.decode(List.filled(8193, 0), newHost), isNull);
    },
  );

  test(
    'simultaneous tube searches share one listener and release it afterward',
    () async {
      var scans = 0;
      final pending = Completer<List<TuyaDiscoveredLight>>();
      final discovery = TuyaLanDiscovery(
        scanner: () {
          scans++;
          return pending.future;
        },
      );
      final a = discovery.discover(), b = discovery.discover();
      expect(scans, 1);
      pending.complete([hint()]);
      expect(await a, await b);
      await discovery.discover();
      expect(scans, 2);
    },
  );

  test(
    'valid saved address performs no discovery and preserves settings',
    () async {
      var scans = 0;
      final raw = FakeTube(tube());
      final client = AutoTuyaClient(
        tube(),
        factory: (_) => raw,
        discover: () async {
          scans++;
          return [hint()];
        },
      );
      addTearDown(client.dispose);
      expect((await client.read()).rawAttributes['connection_host'], oldHost);
      expect(scans, 0);
    },
  );

  test('changed IP is saved only after encrypted client read; timers use recovered client', () async {
    final clients = <FakeTube>[], events = <ResolvedConnection>[];
    final client = AutoTuyaClient(
      tube(),
      discover: () async => [hint()],
      factory: (c) {
        final raw = FakeTube(c, readError: c.host == oldHost ? offline : null);
        clients.add(raw);
        return raw;
      },
      onResolved: events.add,
    );
    addTearDown(client.dispose);
    expect((await client.read()).rawAttributes['connection_host'], newHost);
    expect(events, hasLength(1));
    expect(events.single.current.localKey, tube().localKey);
    expect(events.single.current.deviceId, tube().deviceId);
    expect(events.single.current.version, tube().version);
    expect(clients.first.disposed, true);
    await client.setTimer(
      DateTime.now().add(const Duration(minutes: 1)),
      on: false,
    );
    await client.cancelTimer();
    expect(clients.last.timerWrites, 1);
    expect(clients.last.timerCancels, 1);
  });

  test('wrong IDs, ambiguous matching IDs and public hosts never receive credentials', () async {
    for (final found in [
      [hint(slot: 'tube2')],
      [hint(), hint(host: '192.168.1.76')],
      [hint(host: '8.8.8.8')],
    ]) {
      var creates = 0;
      final client = AutoTuyaClient(
        tube(),
        factory: (c) {
          creates++;
          return FakeTube(c, readError: offline);
        },
        discover: () async => found,
      );
      await expectLater(client.read(), throwsA(isA<DeviceException>()));
      expect(creates, 1);
      client.dispose();
    }
  });

  test('failed key verification never saves discovered address', () async {
    final events = <ResolvedConnection>[], clients = <FakeTube>[];
    final client = AutoTuyaClient(
      tube(),
      discover: () async => [hint()],
      onResolved: events.add,
      factory: (c) {
        final raw = FakeTube(
          c,
          readError: c.host == oldHost
              ? offline
              : const DeviceException(DeviceError.unauthorized, 'Key rejected'),
        );
        clients.add(raw);
        return raw;
      },
    );
    addTearDown(client.dispose);
    await expectLater(client.read(), throwsA(isA<DeviceException>()));
    expect(events, isEmpty);
    expect(client.config.host, oldHost);
    expect(clients.last.disposed, true);
  });

  test(
    'uncertain writes are never replayed or followed by rediscovery',
    () async {
      var scans = 0;
      final raw = FakeTube(tube(), commandError: offline);
      final client = AutoTuyaClient(
        tube(),
        factory: (_) => raw,
        discover: () async {
          scans++;
          return [hint()];
        },
      );
      addTearDown(client.dispose);
      await expectLater(
        client.command(await raw.read(), const LightCommand(on: false)),
        throwsA(isA<DeviceException>()),
      );
      expect(raw.commands, 1);
      expect(scans, 0);
    },
  );

  test(
    'search throttles while powered off, then recovers when tube returns',
    () async {
      var now = DateTime(2026), scans = 0;
      final client = AutoTuyaClient(
        tube(),
        clock: () => now,
        factory: (c) =>
            FakeTube(c, readError: c.host == oldHost ? offline : null),
        discover: () async {
          scans++;
          return scans == 1 ? [] : [hint()];
        },
      );
      addTearDown(client.dispose);
      await expectLater(client.read(), throwsA(isA<DeviceException>()));
      await expectLater(client.read(), throwsA(isA<DeviceException>()));
      expect(scans, 1);
      now = now.add(const Duration(seconds: 31));
      expect((await client.read()).available, true);
      expect(scans, 2);
    },
  );

  test(
    'closing during candidate verification closes candidate and never saves it',
    () async {
      final gate = Completer<void>(),
          clients = <FakeTube>[],
          events = <ResolvedConnection>[];
      final client = AutoTuyaClient(
        tube(),
        discover: () async => [hint()],
        onResolved: events.add,
        factory: (c) {
          final raw = FakeTube(
            c,
            readError: c.host == oldHost ? offline : null,
            pending: c.host == newHost ? gate : null,
          );
          clients.add(raw);
          return raw;
        },
      );
      final result = expectLater(
        client.read(),
        throwsA(isA<DeviceException>()),
      );
      while (clients.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      client.dispose();
      gate.complete();
      await result;
      expect(events, isEmpty);
      expect(clients.every((c) => c.disposed), true);
    },
  );

  test('DHCP address swap persists both verified tubes atomically and keeps scenes', () async {
    final a = tube(), b = tube(slot: 'tube2', host: newHost);
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([a, b, tapoConfig()]);
    final settings = MemorySettings();
    final initialSettings = settings.value;
    final container = ProviderContainer(
      overrides: [
        credentialStoreProvider.overrideWithValue(credentials),
        settingsStoreProvider.overrideWithValue(settings),
        backendFactoryProvider.overrideWithValue(
          (config, demo) => LocalLightsRepository(
            ConnectionConfig(
              config!.devices
                  .where((d) => d.brand == DeviceBrand.tuya)
                  .toList(),
            ),
            tuyaDiscover: () async => [
              hint(host: newHost),
              hint(slot: 'tube2', host: oldHost),
            ],
            tuyaClientFactory: (c) => FakeTube(
              c,
              readError:
                  (c.slotId == 'tube1' ? c.host == oldHost : c.host == newHost)
                  ? offline
                  : null,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appControllerProvider.notifier).initialize();
    await Future<void>.delayed(Duration.zero);
    final saved = credentials.config!.devices;
    expect(saved.firstWhere((d) => d.slotId == 'tube1').host, newHost);
    expect(saved.firstWhere((d) => d.slotId == 'tube2').host, oldHost);
    expect(
      saved.firstWhere((d) => d.slotId == 'strip').toJson(),
      tapoConfig().toJson(),
    );
    expect(identical(settings.value, initialSettings), true);
    final transfer = await container
        .read(appControllerProvider.notifier)
        .configurationForTransfer();
    expect(transfer.devices.first.host, newHost);
  });

  for (final version in TuyaVersion.values) {
    test(
      'real TCP ${version.name} recovers moved tube and rejects a forged UDP hint',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final config = tube(version: version),
            key = utf8.encode('0123456789abcdef');
        var wrongIdentity = false;
        final handlers = <Future<void>>[];
        server.listen((socket) {
          handlers.add(() async {
            final codec = TuyaCodec(version, key),
                remote = List.generate(16, (i) => i + 16);
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
                  final mixed = List.generate(16, (i) => local![i] ^ remote[i]);
                  codec.key = version == TuyaVersion.v35
                      ? aesGcm(mixed, key, local!.sublist(0, 12)).sublist(0, 16)
                      : aesBlock(mixed, key, padding: false);
                } else {
                  socket.add(
                    codec.encode(
                      2,
                      frame.command,
                      utf8.encode(
                        jsonEncode({
                          'gwId': wrongIdentity
                              ? 'other-light'
                              : config.deviceId,
                          'dps': {
                            '20': true,
                            '21': 'white',
                            '22': 500,
                            '23': 500,
                            '24': '000003e803e8',
                          },
                        }),
                      ),
                      withVersion: true,
                      returnCode: 0,
                    ),
                  );
                }
              }
            } finally {
              socket.destroy();
            }
          }());
        });
        DeviceClient factory(DeviceConnection c) => TuyaClient(
          c,
          transport: TuyaTransport(
            c,
            connector: (host, port) {
              if (host == oldHost) throw const SocketException('Offline');
              return Socket.connect(InternetAddress.loopbackIPv4, server.port);
            },
          ),
        );
        final events = <ResolvedConnection>[];
        final client = AutoTuyaClient(
          config,
          factory: factory,
          discover: () async => [hint()],
          onResolved: events.add,
        );
        expect((await client.read()).brightnessPercent, 50);
        expect(events.single.current.host, newHost);
        client.dispose();
        wrongIdentity = true;
        events.clear();
        final forged = AutoTuyaClient(
          config,
          factory: factory,
          discover: () async => [hint()],
          onResolved: events.add,
        );
        await expectLater(forged.read(), throwsA(isA<DeviceException>()));
        expect(events, isEmpty);
        forged.dispose();
        await Future.wait(handlers);
      },
    );
  }
}
