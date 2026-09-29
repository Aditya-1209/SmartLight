import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/lights_repository.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/device_client.dart';

import 'support.dart';

class FakeLight implements DeviceClient {
  FakeLight(this.config, {this.fail = false});
  final DeviceConnection config;
  bool fail, closed = false;
  @override
  Future<LightEntity> read() async {
    if (fail) {
      throw const DeviceException(DeviceError.unreachable, 'Device offline.');
    }
    return LightEntity(
      entityId: config.entityId,
      friendlyName: config.name,
      state: 'on',
      attributes: {},
    );
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) async {}
  @override
  void dispose() {
    closed = true;
  }
}

class UnavailableCredentials extends MemoryCredentials {
  bool unavailable = true;
  int writes = 0;
  @override
  Future<ConnectionConfig?> read() async {
    if (unavailable) throw StateError('test storage unavailable');
    return super.read();
  }

  @override
  Future<void> write(ConnectionConfig value) async {
    writes++;
    await super.write(value);
  }
}

void main() {
  test('Retry reloads credentials after a transient startup failure', () async {
    final credentials = UnavailableCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final container = testContainer(demo: false, credentials: credentials);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(container.read(appControllerProvider).error, isNotNull);
    credentials.unavailable = false;
    await controller.refresh();
    expect(
      container.read(appControllerProvider).config?.devices.single.slotId,
      'strip',
    );
    expect(container.read(appControllerProvider).connected, isTrue);
  });
  test('saving or removing cannot overwrite unread credentials', () async {
    final credentials = UnavailableCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final container = testContainer(demo: false, credentials: credentials);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    await expectLater(
      controller.saveDevice(tapoConfig(name: 'New')),
      throwsA(isA<DeviceException>()),
    );
    await expectLater(
      controller.removeDevice('strip'),
      throwsA(isA<DeviceException>()),
    );
    await expectLater(
      controller.importConnections(ConnectionConfig([tapoConfig()])),
      throwsA(isA<DeviceException>()),
    );
    await expectLater(
      controller.configurationForTransfer(),
      throwsA(isA<DeviceException>()),
    );
    expect(credentials.writes, 0);
    expect(credentials.config?.devices.single.name, 'Tapo Strip');
  });
  test(
    'one disconnected light does not hide or disable its connected peer',
    () async {
      final tube = DeviceConnection(
        slotId: 'tube1',
        name: 'Tube',
        brand: DeviceBrand.tuya,
        host: '192.168.1.2',
        deviceId: 'demo',
        localKey: '0123456789abcdef',
      );
      final clients = <FakeLight>[];
      final repo = LocalLightsRepository(
        ConnectionConfig([tube, tapoConfig()]),
        factory: (c) {
          final client = FakeLight(c, fail: c.slotId == 'tube1');
          clients.add(client);
          return client;
        },
      );
      final lights = await repo.getLights();
      expect(lights.first.available, false);
      expect(lights.last.available, true);
      expect(lights.first.rawAttributes['connection_error'], 'Device offline.');
      repo.dispose();
      expect(clients.every((c) => c.closed), true);
    },
  );
  test('background releases connections; reopening reconnects; remove last light clears setup', () async {
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final container = testContainer(demo: false, credentials: credentials);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(container.read(appControllerProvider).connected, true);
    await controller.setForeground(false);
    expect(container.read(appControllerProvider).connected, false);
    await controller.setForeground(true);
    expect(container.read(appControllerProvider).connected, true);
    await controller.removeDevice('strip');
    expect(credentials.config!.devices, isEmpty);
    expect(container.read(appControllerProvider).configured, false);
  });
  test('simultaneous setup saves keep both devices', () async {
    final credentials = MemoryCredentials();
    final container = testContainer(demo: false, credentials: credentials);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    final tube = DeviceConnection(
      slotId: 'tube1',
      name: 'Tube',
      brand: DeviceBrand.tuya,
      host: '192.168.1.2',
      deviceId: 'demo',
      localKey: '0123456789abcdef',
    );
    await Future.wait([
      controller.saveDevice(tapoConfig()),
      controller.saveDevice(tube),
    ]);
    expect(credentials.config!.devices.map((d) => d.slotId).toSet(), {
      'strip',
      'tube1',
    });
  });
  test(
    'imports merge slots atomically and reject conflicting addresses',
    () async {
      final credentials = MemoryCredentials()
        ..config = ConnectionConfig([tapoConfig()]);
      final container = testContainer(demo: false, credentials: credentials);
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      DeviceConnection tube(String host) => DeviceConnection(
        slotId: 'tube1',
        name: 'New tube',
        brand: DeviceBrand.tuya,
        host: host,
        deviceId: 'synthetic-device',
        localKey: '0123456789abcdef',
      );
      await expectLater(
        controller.importConnections(ConnectionConfig([tube('192.168.1.50')])),
        throwsA(isA<DeviceException>()),
      );
      expect(credentials.config!.devices, hasLength(1));
      await controller.importConnections(
        ConnectionConfig([tube('192.168.1.25')]),
      );
      expect(credentials.config!.devices.map((d) => d.slotId).toSet(), {
        'strip',
        'tube1',
      });
      await controller.importConnections(
        ConnectionConfig([tapoConfig(name: 'Renamed strip')]),
      );
      expect(credentials.config!.devices, hasLength(2));
      expect(
        credentials.config!.devices
            .singleWhere((d) => d.slotId == 'strip')
            .name,
        'Renamed strip',
      );
      expect(await controller.configurationForTransfer(), credentials.config);
    },
  );
  test('secure configuration round trip redacts toString and prevents duplicate devices', () {
    final config = ConnectionConfig([tapoConfig()]);
    expect(
      ConnectionConfig.fromJson(config.toJson()).devices.single.password,
      'test-password',
    );
    expect(config.toString(), isNot(contains('test-password')));
    expect(config.devices.single.toString(), isNot(contains('test-password')));
    expect(
      () => ConnectionConfig([tapoConfig(), tapoConfig()]),
      throwsA(isA<DeviceException>()),
    );
  });
  test('per-device queue serializes overlapping polls and commands and survives errors', () async {
    final queue = DeviceQueue(), first = Completer<void>();
    final order = <int>[];
    final a = queue.run(() async {
      order.add(1);
      await first.future;
      order.add(2);
    });
    final b = queue.run(() async {
      order.add(3);
      throw const FormatException();
    });
    final handled = expectLater(b, throwsFormatException);
    final c = queue.run(() async {
      order.add(4);
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    first.complete();
    await a;
    await handled;
    await c;
    expect(order, [1, 2, 3, 4]);
  });
}
