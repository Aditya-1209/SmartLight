import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/screens/settings/wipro_pairing_screen.dart';
import 'package:smart_light/services/pairing/tuya_pairing.dart';

void main() {
  testWidgets(
    'setup waits for consent, pairs one light and closes its SDK session',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const channel = MethodChannel('smartlight/tuya_pairing');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'available' => true,
          'prepare' => <dynamic>[],
          'pair' => {
            'deviceId': 'test-tube',
            'localKey': '0123456789abcdef',
            'host': '192.168.1.50',
            'version': '3.3',
            'dpIds': ['20'],
          },
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PairedTuyaDevice? paired;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  paired = await Navigator.of(context).push<PairedTuyaDevice>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const WiproPairingScreen(lightName: 'Tube 1'),
                    ),
                  );
                },
                child: const Text('Open setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open setup'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Continue with Tuya setup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Home Wi-Fi name (SSID)'),
        'Room Wi-Fi',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Home Wi-Fi password'),
        'test-wifi-password',
      );
      await tester.ensureVisible(find.text('This tube is blinking quickly'));
      await tester.tap(find.text('This tube is blinking quickly'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prepare pairing'));
      await tester.tap(find.text('Prepare pairing'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start pairing'));
      await tester.tap(find.text('Start pairing'));
      await tester.pumpAndSettle();
      expect(paired?.deviceId, 'test-tube');
      expect(paired?.hasLocalKey, isTrue);
      expect(calls.map((c) => c.method), [
        'available',
        'prepare',
        'permissions',
        'token',
        'pair',
        'close',
      ]);
      final request =
          calls.singleWhere((c) => c.method == 'pair').arguments as Map;
      expect(request['ssid'], 'Room Wi-Fi');
      expect(request['mode'], 'EZ');
      expect(find.textContaining('0123456789abcdef'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
