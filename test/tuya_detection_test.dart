import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/lights_repository.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/local/device_client.dart';
import 'package:smart_light/services/local/tuya_protocol.dart';

import 'support.dart';

DeviceConnection tube() => DeviceConnection(
  slotId: 'tube1',
  name: 'Fixture tube',
  brand: DeviceBrand.tuya,
  host: '192.168.1.25',
  deviceId: 'synthetic-device',
  localKey: '0123456789abcdef',
);

class ProbeClient implements DeviceClient {
  ProbeClient(this.config, this.error);
  final DeviceConnection config;
  final DeviceException? error;
  bool disposed = false;
  @override
  Future<LightEntity> read() async {
    if (error != null) throw error!;
    return LightEntity(
      entityId: config.entityId,
      friendlyName: config.name,
      state: 'on',
      attributes: {},
    );
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) async =>
      fail('Detection must never control a light.');
  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ProviderContainer containerFor(
    List<ProbeClient> clients,
    DeviceException? Function(TuyaVersion) error,
    MemoryCredentials credentials,
  ) => ProviderContainer(
    overrides: [
      credentialStoreProvider.overrideWithValue(credentials),
      settingsStoreProvider.overrideWithValue(MemorySettings()),
      backendFactoryProvider.overrideWithValue(
        (config, demo) => LocalLightsRepository(
          config!,
          factory: (device) {
            final client = ProbeClient(device, error(device.version));
            clients.add(client);
            return client;
          },
        ),
      ),
    ],
  );

  test(
    'detection stops on a verified response, closes attempts and does not save',
    () async {
      final clients = <ProbeClient>[];
      final credentials = MemoryCredentials();
      final container = containerFor(
        clients,
        (v) => v == TuyaVersion.v34
            ? null
            : const TuyaTimeoutException(TuyaConnectionStage.status),
        credentials,
      );
      addTearDown(container.dispose);
      final progress = <TuyaVersion>[];
      final result = await container
          .read(appControllerProvider.notifier)
          .detectTuyaProtocol(tube(), onTrying: progress.add);
      expect(progress, [TuyaVersion.v33, TuyaVersion.v34]);
      expect(result.version, TuyaVersion.v34);
      expect(result.deviceId, tube().deviceId);
      expect(result.localKey, tube().localKey);
      expect(clients.every((c) => c.disposed), isTrue);
      expect(credentials.config, isNull);
    },
  );

  test(
    'failed detection tries each protocol once and redacts arbitrary errors',
    () async {
      final clients = <ProbeClient>[];
      final credentials = MemoryCredentials();
      final container = containerFor(
        clients,
        (_) => const DeviceException(
          DeviceError.timeout,
          'private 0123456789abcdef',
        ),
        credentials,
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(appControllerProvider.notifier)
            .detectTuyaProtocol(tube()),
        throwsA(
          isA<DeviceException>().having(
            (e) => e.message,
            'diagnostic',
            allOf(
              contains('3.3'),
              contains('3.4'),
              contains('3.5'),
              isNot(contains('0123456789abcdef')),
            ),
          ),
        ),
      );
      expect(clients.map((c) => c.config.version), TuyaVersion.values);
      expect(clients.every((c) => c.disposed), isTrue);
      expect(credentials.config, isNull);
    },
  );

  test('network failure and leaving setup stop further attempts', () async {
    for (final unreachable in [true, false]) {
      final clients = <ProbeClient>[];
      final container = containerFor(
        clients,
        (_) => TuyaTimeoutException(
          unreachable
              ? TuyaConnectionStage.connecting
              : TuyaConnectionStage.status,
        ),
        MemoryCredentials(),
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(appControllerProvider.notifier)
            .detectTuyaProtocol(tube(), stillWanted: () => clients.isEmpty),
        throwsA(isA<DeviceException>()),
      );
      expect(clients, hasLength(1));
      expect(clients.single.disposed, isTrue);
    }
  });

  test(
    'real sockets distinguish a silent status request from a silent handshake',
    () async {
      for (final version in TuyaVersion.values) {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = <Socket>[];
        server.listen((socket) {
          accepted.add(socket);
          socket.listen((_) {});
        });
        final config = DeviceConnection.fromJson({
          ...tube().toJson(),
          'version': version.name,
        });
        final transport = TuyaTransport(
          config,
          timeout: const Duration(milliseconds: 150),
          connector: (_, _) =>
              Socket.connect(InternetAddress.loopbackIPv4, server.port),
        );
        try {
          await expectLater(
            transport.exchange(),
            throwsA(
              isA<TuyaTimeoutException>().having(
                (e) => e.stage,
                'stage',
                version == TuyaVersion.v33
                    ? TuyaConnectionStage.status
                    : TuyaConnectionStage.handshake,
              ),
            ),
          );
        } finally {
          transport.dispose();
          for (final socket in accepted) {
            socket.destroy();
          }
          await server.close();
        }
      }
    },
  );

  testWidgets('Auto finds and saves the detected version from the setup form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clients = <ProbeClient>[];
    final credentials = MemoryCredentials();
    final container = containerFor(
      clients,
      (v) => v == TuyaVersion.v34
          ? null
          : const TuyaTimeoutException(TuyaConnectionStage.status),
      credentials,
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SmartLightApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your lights'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connected lights'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('expand-tube1')));
    await tester.tap(find.byKey(const ValueKey('expand-tube1')));
    await tester.pumpAndSettle();
    for (final entry in {
      'tube1-host': '192.168.1.25',
      'tube1-device-id': 'synthetic-device',
      'tube1-local-key': '0123456789abcdef',
    }.entries) {
      await tester.ensureVisible(find.byKey(ValueKey(entry.key)));
      await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
    }
    final auto = find.byKey(const ValueKey('protocol-tube1-auto'));
    await tester.ensureVisible(auto);
    expect(auto, findsOneWidget);
    final card = find.byKey(const ValueKey('setup-tube1'));
    final testButton = find.descendant(
      of: card,
      matching: find.text('Test connection'),
    );
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Connected. This light is ready to save.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('protocol-tube1-v34')), findsOneWidget);
    expect(credentials.config, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('save-tube1')));
    await tester.tap(find.byKey(const ValueKey('save-tube1')));
    await tester.pumpAndSettle();
    expect(credentials.config!.devices.single.version, TuyaVersion.v34);
    expect(tester.takeException(), isNull);
    await container.read(appControllerProvider.notifier).setForeground(false);
  });
}
