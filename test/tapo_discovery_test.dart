import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/light_timer.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/lights_repository.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/auto_tapo_client.dart';
import 'package:smart_light/services/local/device_client.dart';
import 'package:smart_light/services/local/device_timer_client.dart';
import 'package:smart_light/services/local/tapo_discovery.dart';

import 'support.dart';

const mac = '40:AE:30:00:11:22';
const otherMac = '40:AE:30:00:11:24';
const newHost = '192.168.1.75';
const candidate = TapoDiscoveredLight(
  host: newHost,
  macAddress: mac,
  model: 'L920',
);
const offline = DeviceException(DeviceError.timeout, 'Offline');

class FakeTapo implements DeviceClient {
  FakeTapo({this.macAddress = mac, this.readError, this.commandError});
  String macAddress;
  Object? readError, commandError;
  int reads = 0, commands = 0;
  bool disposed = false;
  @override
  Future<LightEntity> read() async {
    reads++;
    if (readError != null) throw readError!;
    return LightEntity(
      entityId: 'light.strip',
      friendlyName: 'Strip',
      state: 'on',
      attributes: {'device_mac': macAddress, 'brightness': 120},
    );
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) async {
    commands++;
    if (commandError != null) throw commandError!;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class FakeTimerTapo extends FakeTapo implements DeviceTimerClient {
  FakeTimerTapo({super.macAddress, super.readError});
  int timerWrites = 0;
  Object? timerError;
  @override
  Future<LightTimerStatus> readTimer() async =>
      const LightTimerStatus(isOn: true);
  @override
  Future<LightTimerStatus> setTimer(DateTime endsAt, {required bool on}) async {
    timerWrites++;
    if (timerError != null) throw timerError!;
    return LightTimerStatus(
      isOn: true,
      active: LightTimer(id: 'fixture', endsAt: endsAt, on: on),
    );
  }

  @override
  Future<LightTimerStatus> cancelTimer() async {
    timerWrites++;
    return readTimer();
  }
}

void main() {
  test('timer writes rediscover and authenticate identity; uncertain writes are not replayed', () async {
    final old = FakeTimerTapo(readError: offline), moved = FakeTimerTapo();
    var discoveries = 0;
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (config) => config.host == newHost ? moved : old,
      discover: () async {
        discoveries++;
        return [candidate];
      },
    );
    addTearDown(client.dispose);
    await client.setTimer(
      DateTime.now().add(const Duration(minutes: 2)),
      on: false,
    );
    expect(old.timerWrites, 0);
    expect(moved.timerWrites, 1);
    expect(discoveries, 1);
    moved.timerError = offline;
    await expectLater(
      client.setTimer(
        DateTime.now().add(const Duration(minutes: 2)),
        on: false,
      ),
      throwsA(same(offline)),
    );
    expect(moved.timerWrites, 2);
    expect(discoveries, 1);
    moved.macAddress = otherMac;
    await expectLater(client.cancelTimer(), throwsA(isA<DeviceException>()));
    expect(moved.timerWrites, 2);
  });
  List<int> packet({String type = 'SMART.TAPOBULB', String address = mac}) => [
    ...List.filled(16, 0),
    ...utf8.encode(
      jsonEncode({
        'error_code': 0,
        'result': {
          'device_type': type,
          'device_model': 'L920-5(EU)',
          'mac': address,
          'ip': '8.8.8.8',
        },
      }),
    ),
  ];
  test('discovery uses local sender and normalized identity, rejects unrelated/unbounded packets', () {
    final result = TapoDiscovery.decode(
      packet(address: '40-ae-30-00-11-22'),
      newHost,
      20002,
    )!;
    expect(result.host, newHost);
    expect(result.macAddress, mac);
    expect(TapoDiscovery.decode(packet(), '8.8.8.8', 20002), isNull);
    expect(TapoDiscovery.decode(packet(), newHost, 80), isNull);
    expect(
      TapoDiscovery.decode(packet(type: 'SMART.TAPOPLUG'), newHost, 20002),
      isNull,
    );
    expect(
      TapoDiscovery.decode(packet(address: 'garbage'), newHost, 20002),
      isNull,
    );
    expect(TapoDiscovery.decode(List.filled(8193, 0), newHost, 20002), isNull);
    expect(TapoDiscovery.decode([0, 1, 2], newHost, 20002), isNull);
  });

  test('legacy connections still load; identity survives secure serialization and address edits', () {
    final legacy = tapoConfig().toJson()..remove('macAddress');
    final original = DeviceConnection.fromJson(legacy);
    expect(original.macAddress, '');
    final moved = original.withAddress(
      host: newHost,
      macAddress: mac.toLowerCase(),
    );
    final restored = ConnectionConfig.fromJson(
      ConnectionConfig([moved]).toJson(),
    ).devices.single;
    expect(restored.macAddress, mac);
    expect(restored.host, newHost);
    expect(restored.password, original.password);
    expect(restored.email, original.email);
    expect(restored.name, original.name);
  });

  test(
    'learns hardware identity only from successful authenticated read',
    () async {
      final events = <ResolvedConnection>[];
      var scans = 0;
      final raw = FakeTapo();
      final client = AutoTapoClient(
        tapoConfig(),
        factory: (_) => raw,
        discover: () async {
          scans++;
          return [candidate];
        },
        onResolved: events.add,
      );
      addTearDown(client.dispose);
      await client.read();
      await client.read();
      expect(events, hasLength(1));
      expect(client.config.macAddress, mac);
      expect(scans, 0);
    },
  );

  test('recovers changed address and confirms identity before saving or controlling', () async {
    final old = FakeTapo(readError: offline), next = FakeTapo();
    final events = <ResolvedConnection>[];
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (c) => c.host == newHost ? next : old,
      discover: () async => [candidate],
      onResolved: events.add,
    );
    addTearDown(client.dispose);
    final light = await client.read();
    expect(client.config.host, newHost);
    expect(events.single.current.macAddress, mac);
    expect(old.disposed, true);
    expect(next.commands, 0);
    await client.command(light, const LightCommand(on: false));
    expect(next.reads, 2);
    expect(next.commands, 1);
  });

  test('spoofed hint / wrong authenticated identity never saves or sends a command', () async {
    final old = FakeTapo(readError: offline),
        wrong = FakeTapo(macAddress: otherMac);
    final events = <ResolvedConnection>[];
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (c) => c.host == newHost ? wrong : old,
      discover: () async => [candidate],
      onResolved: events.add,
    );
    addTearDown(client.dispose);
    await expectLater(client.read(), throwsA(isA<DeviceException>()));
    expect(client.config.host, tapoConfig().host);
    expect(events, isEmpty);
    expect(wrong.commands, 0);
    expect(wrong.disposed, true);
  });

  test('old address reused by another light is detected even with valid account credentials', () async {
    final old = FakeTapo(macAddress: otherMac), next = FakeTapo();
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (c) => c.host == newHost ? next : old,
      discover: () async => [candidate],
    );
    addTearDown(client.dispose);
    await client.command(await next.read(), const LightCommand(on: false));
    expect(old.commands, 0);
    expect(next.commands, 1);
  });

  test('legacy stale address requires explicit selection, never adopts an arbitrary light', () async {
    var scans = 0;
    final client = AutoTapoClient(
      tapoConfig(),
      factory: (_) => FakeTapo(readError: offline),
      discover: () async {
        scans++;
        return [candidate];
      },
    );
    addTearDown(client.dispose);
    await expectLater(
      client.read(),
      throwsA(
        isA<DeviceException>().having(
          (e) => e.message,
          'message',
          contains('Find Tapo light'),
        ),
      ),
    );
    expect(scans, 0);
    expect(client.config.macAddress, '');
  });

  test('failed discovery is throttled, retries later, and does not follow another MAC', () async {
    var now = DateTime(2026), scans = 0;
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (_) => FakeTapo(readError: offline),
      clock: () => now,
      discover: () async {
        scans++;
        return [
          const TapoDiscoveredLight(
            host: newHost,
            macAddress: otherMac,
            model: 'L920',
          ),
        ];
      },
    );
    addTearDown(client.dispose);
    for (var i = 0; i < 2; i++) {
      await expectLater(client.read(), throwsA(isA<DeviceException>()));
    }
    expect(scans, 1);
    now = now.add(const Duration(seconds: 31));
    await expectLater(client.read(), throwsA(isA<DeviceException>()));
    expect(scans, 2);
  });

  test('ambiguous discovery and disposal during search do not open candidate connections', () async {
    var created = 0;
    final pending = Completer<List<TapoDiscoveredLight>>();
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (_) {
        created++;
        return FakeTapo(readError: offline);
      },
      discover: () => pending.future,
    );
    final read = client.read();
    final expectRead = expectLater(read, throwsA(isA<DeviceException>()));
    await Future<void>.delayed(Duration.zero);
    client.dispose();
    pending.complete([candidate]);
    await expectRead;
    expect(created, 1);
    final ambiguous = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (_) {
        created++;
        return FakeTapo(readError: offline);
      },
      discover: () async => [
        candidate,
        const TapoDiscoveredLight(
          host: '192.168.1.76',
          macAddress: mac,
          model: 'L920',
        ),
      ],
    );
    addTearDown(ambiguous.dispose);
    await expectLater(ambiguous.read(), throwsA(isA<DeviceException>()));
    expect(created, 2);
  });

  test('uncertain command is not replayed or followed by discovery', () async {
    final raw = FakeTapo(commandError: offline);
    var scans = 0;
    final client = AutoTapoClient(
      tapoConfig().withAddress(macAddress: mac),
      factory: (_) => raw,
      discover: () async {
        scans++;
        return [candidate];
      },
    );
    addTearDown(client.dispose);
    await expectLater(
      client.command(await raw.read(), const LightCommand(on: false)),
      throwsA(isA<DeviceException>()),
    );
    expect(raw.commands, 1);
    expect(scans, 0);
  });

  test('controller persists recovered address and preserves other connections/settings', () async {
    final tube = DeviceConnection(
      slotId: 'tube1',
      name: 'Tube',
      brand: DeviceBrand.tuya,
      host: '192.168.1.30',
      deviceId: 'test-id',
      localKey: '0123456789abcdef',
    );
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([
        tube,
        tapoConfig().withAddress(macAddress: mac),
      ]);
    final settings = MemorySettings();
    final container = ProviderContainer(
      overrides: [
        credentialStoreProvider.overrideWithValue(credentials),
        settingsStoreProvider.overrideWithValue(settings),
        backendFactoryProvider.overrideWithValue(
          (config, demo) => LocalLightsRepository(
            ConnectionConfig(
              config!.devices
                  .where((d) => d.brand == DeviceBrand.tapo)
                  .toList(),
            ),
            tapoClientFactory: (c) =>
                FakeTapo(readError: c.host == newHost ? null : offline),
            tapoDiscover: () async => [candidate],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final originalSettings = settings.value;
    await container.read(appControllerProvider.notifier).initialize();
    await Future<void>.delayed(Duration.zero);
    expect(
      credentials.config!.devices.where((d) => d.slotId == 'strip').single.host,
      newHost,
    );
    expect(
      credentials.config!.devices
          .where((d) => d.slotId == 'tube1')
          .single
          .localKey,
      tube.localKey,
    );
    expect(identical(settings.value, originalSettings), true);
    final transfer = await container
        .read(appControllerProvider.notifier)
        .configurationForTransfer();
    expect(
      transfer.devices.where((d) => d.slotId == 'strip').single.macAddress,
      mac,
    );
  });
}
