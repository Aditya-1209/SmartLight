import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/device_slot.dart';
import 'package:smart_light/screens/settings/settings_screen.dart';
import 'package:smart_light/services/local/tuya_lan_discovery.dart';

import 'tuya_address_recovery_test.dart' show tube, oldHost, newHost;

void main() {
  testWidgets(
    'Find this tube uses saved ID and preserves masked key until verified save',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          tuyaDiscoveryProvider.overrideWithValue(
            () async => [
              const TuyaDiscoveredLight(
                deviceId: 'synthetic-tube2',
                host: '192.168.1.76',
              ),
              const TuyaDiscoveredLight(
                deviceId: 'synthetic-tube1',
                host: newHost,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeviceSetupCard(
                  slot: DeviceSlot.defaults.first,
                  saved: tube(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expand-tube1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Find this tube'));
      await tester.tap(find.text('Find this tube'));
      await tester.pumpAndSettle();
      final host = tester.widget<TextField>(
        find.byKey(const ValueKey('tube1-host')),
      );
      final key = tester.widget<TextField>(
        find.byKey(const ValueKey('tube1-local-key')),
      );
      expect(host.controller!.text, newHost);
      expect(key.controller!.text, tube().localKey);
      expect(key.obscureText, true);
      expect(
        find.textContaining('Choose Connect & save to verify its existing key'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('background tube address changes preserve unfinished edits', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Future<void> show(String host) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DeviceSetupCard(
                key: const ValueKey('tube-card'),
                slot: DeviceSlot.defaults.first,
                saved: tube(host: host),
              ),
            ),
          ),
        ),
      ),
    );
    await show(oldHost);
    await tester.tap(find.byKey(const ValueKey('expand-tube1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tube1-name')));
    await tester.enterText(
      find.byKey(const ValueKey('tube1-name')),
      'Edited tube name',
    );
    await show(newHost);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tube1-name')))
          .controller!
          .text,
      'Edited tube name',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tube1-host')))
          .controller!
          .text,
      newHost,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('tube1-host')));
    await tester.enterText(
      find.byKey(const ValueKey('tube1-host')),
      '192.168.1.99',
    );
    await show('192.168.1.76');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tube1-host')))
          .controller!
          .text,
      '192.168.1.99',
    );
    expect(tester.takeException(), isNull);
  });
}
