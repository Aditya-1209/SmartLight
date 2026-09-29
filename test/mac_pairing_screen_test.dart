import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/screens/settings/mac_wipro_pairing_screen.dart';
import 'package:smart_light/services/pairing/desktop_tuya_pairing.dart';
import 'package:smart_light/services/pairing/tuya_cloud_setup.dart';
import 'package:smart_light/services/pairing/tuya_pairing.dart';

class FakePairing extends DesktopTuyaPairing {
  int checks = 0, pairs = 0;
  bool closed = false;
  @override
  Future<TuyaCloudConfig?> savedConfig() async => const TuyaCloudConfig(
    clientId: 'testclientid1234',
    secret: 'testsecretvalue123',
    schema: 'testschema',
  );
  @override
  Future<List<PairedTuyaDevice>> prepare(TuyaCloudConfig config) async {
    checks++;
    if (checks == 1) throw const TuyaSetupException('Test project not linked');
    return [];
  }

  @override
  Future<Map<String, String>> networkAddresses() async => {
    '192.168.1.5': 'en0 · 192.168.1.5',
  };
  @override
  Future<PairedTuyaDevice> pair({
    required String ssid,
    required String password,
    required String bindAddress,
  }) async {
    pairs++;
    expect(ssid, 'Room Wi-Fi');
    expect(password, 'testwifi');
    expect(bindAddress, '192.168.1.5');
    return PairedTuyaDevice.fromMap({
      'deviceId': 'fake-light',
      'localKey': '0123456789abcdef',
      'host': '192.168.1.50',
      'version': '3.3',
    });
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  testWidgets(
    'Mac pairing checks access before showing reset and requires blinking consent',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pairing = FakePairing();
      PairedTuyaDevice? device;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  device = await Navigator.of(context).push<PairedTuyaDevice>(
                    MaterialPageRoute(
                      builder: (_) => MacWiproPairingScreen(
                        lightName: 'Tube 1',
                        pairing: pairing,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(pairing.checks, 0);
      expect(find.text('Pair this tube'), findsNothing);
      await tester.tap(find.text('Check setup'));
      await tester.pumpAndSettle();
      expect(find.text('Test project not linked'), findsOneWidget);
      expect(find.text('Pair this tube'), findsNothing);
      await tester.tap(find.text('Check setup'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Pair this tube'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Home Wi-Fi name (SSID)'),
        'Room Wi-Fi',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Home Wi-Fi password'),
        'testwifi',
      );
      await tester.tap(find.text('Only this tube is blinking quickly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair this tube'));
      await tester.pumpAndSettle();
      expect(device?.deviceId, 'fake-light');
      expect(pairing.pairs, 1);
      expect(pairing.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
