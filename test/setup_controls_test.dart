import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/services/demo_lights.dart';
import 'package:smart_light/widgets/brightness_slider.dart';
import 'package:smart_light/widgets/color_picker.dart';

import 'support.dart';

class CapabilityBackend extends DemoLights {
  CapabilityBackend() : super(latency: Duration.zero);
  @override
  Future<List<LightEntity>> getLights() async =>
      (await super.getLights()).map((light) {
        return LightEntity.fromJson({
          ...light.toJson(),
          'attributes': {
            ...light.rawAttributes,
            'supported_color_modes': light.entityId.contains('tube_1')
                ? ['onoff']
                : light.entityId.contains('tube_2')
                ? ['brightness']
                : ['color_temp'],
          },
        });
      }).toList();
}

void main() {
  Future<void> show(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
  }

  testWidgets('connect and save a single Tapo light with masked credentials', (
    tester,
  ) async {
    final credentials = MemoryCredentials();
    final settings = MemorySettings();
    final container = testContainer(
      demo: false,
      credentials: credentials,
      settings: settings,
    );
    await show(tester, container);
    await tester.tap(find.text('Add your lights'));
    await tester.pumpAndSettle();
    for (final entry in {
      'strip-host': '192.168.1.50',
      'strip-email': 'test@example.com',
      'strip-password': 'test-password',
      'strip-name': 'Desk strip',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('strip-password')))
          .obscureText,
      true,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-strip')));
    await tester.tap(find.byKey(const ValueKey('save-strip')));
    await tester.pumpAndSettle();
    expect(find.text('Connected and saved securely.'), findsOneWidget);
    expect(credentials.config!.devices.single.password, 'test-password');
    expect(credentials.config!.devices.single.name, 'Desk strip');
    expect(
      settings.value.toJson().toString(),
      isNot(contains('test-password')),
    );
    expect(container.read(appControllerProvider).settings.demo, false);
    expect(
      container
          .read(appControllerProvider)
          .slots
          .where((s) => s.entityId != null)
          .length,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'details hide unsupported controls and disable unavailable power',
    (tester) async {
      final backend = CapabilityBackend();
      final container = testContainer(backend: backend);
      await show(tester, container);
      await tester.ensureVisible(find.text('Wipro Tube 1'));
      await tester.tap(find.text('Wipro Tube 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ValueSlider), findsNothing);
      expect(find.byType(LightColorPicker), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Wipro Tube 2'));
      await tester.tap(find.text('Wipro Tube 2'));
      await tester.pumpAndSettle();
      expect(find.byType(ValueSlider), findsOneWidget);
      expect(find.byType(LightColorPicker), findsNothing);
      backend.setAvailable('light.wipro_tube_2', false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('detail-power')))
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('brightness slider issues a command only after drag ends', (
    tester,
  ) async {
    final container = testContainer();
    await show(tester, container);
    final slider = find.descendant(
      of: find.byKey(const ValueKey('master-brightness')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    final initial = container
        .read(appControllerProvider)
        .lights['light.tapo_strip']!
        .brightness;
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(
      container
          .read(appControllerProvider)
          .lights['light.tapo_strip']!
          .brightness,
      initial,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final lights = container.read(appControllerProvider).lights.values;
    expect(lights.map((l) => l.brightness).toSet().length, 1);
    expect(lights.first.brightness, isNot(initial));
  });
}
