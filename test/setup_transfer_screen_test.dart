import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/screens/settings/setup_transfer_screen.dart';
import 'package:smart_light/screens/settings/settings_screen.dart';
import 'package:smart_light/services/setup_transfer.dart';

import 'support.dart';

class FakeTransfer extends SetupTransfer {
  @override
  Future<ConnectionConfig> open(String code, String password) async {
    expect(code, 'synthetic-code');
    expect(password, 'synthetic-password');
    return ConnectionConfig([
      DeviceConnection(
        slotId: 'tube1',
        name: 'Imported tube',
        brand: DeviceBrand.tuya,
        host: '192.168.1.25',
        deviceId: 'fixture-device',
        localKey: '0123456789abcdef',
      ),
    ]);
  }
}

void main() {
  testWidgets(
    'receiving requires review and explicit save, and preserves other lights',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final credentials = MemoryCredentials()
        ..config = ConnectionConfig([tapoConfig()]);
      final container = ProviderContainer(
        overrides: [
          credentialStoreProvider.overrideWithValue(credentials),
          settingsStoreProvider.overrideWithValue(
            MemorySettings(const AppSettings()),
          ),
          backendFactoryProvider.overrideWithValue(
            (config, demo) => ConfiguredDemo(config!),
          ),
          setupTransferProvider.overrideWithValue(FakeTransfer()),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(appControllerProvider.notifier).initialize(),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SettingsScreen()),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Use lights on another device'));
      await tester.tap(find.text('Use lights on another device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receive setup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transfer-code')),
        'synthetic-code',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transfer-password')),
        'synthetic-password',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unlock and review'));
      await tester.tap(find.text('Unlock and review'));
      await tester.pumpAndSettle();
      expect(credentials.config!.devices, hasLength(1));
      expect(find.text('Imported tube'), findsOneWidget);
      await tester.ensureVisible(find.text('Save selected lights'));
      await tester.tap(find.text('Save selected lights'));
      await tester.pumpAndSettle();
      expect(credentials.config!.devices.map((d) => d.slotId).toSet(), {
        'strip',
        'tube1',
      });
      expect(find.textContaining('Connections saved securely'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('expand-tube1')));
      await tester.tap(find.byKey(const ValueKey('expand-tube1')));
      await tester.pumpAndSettle();
      final host = tester.widget<TextField>(
        find.byKey(const ValueKey('tube1-host')),
      );
      expect(host.controller!.text, '192.168.1.25');
      final key = tester.widget<TextField>(
        find.byKey(const ValueKey('tube1-local-key')),
      );
      expect(key.controller!.text, '0123456789abcdef');
      expect(key.obscureText, isTrue);
      expect(tester.takeException(), isNull);
      await container.read(appControllerProvider.notifier).setForeground(false);
    },
  );
}
