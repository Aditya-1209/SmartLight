import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/providers/app_controller.dart';

import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'configure demo, control a light, change brightness/color, apply Movie',
    (tester) async {
      final container = testContainer(demo: false);
      addTearDown(container.dispose);
      await container.read(appControllerProvider.notifier).initialize();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SmartLightApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-demo')));
      await tester.pumpAndSettle();
      for (final id in ['tube1', 'tube2', 'strip']) {
        expect(find.byKey(ValueKey('device-$id')), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('power-tube1')));
      await tester.tap(find.byKey(const ValueKey('power-tube1')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appControllerProvider)
            .lights['light.wipro_tube_1']!
            .isOn,
        false,
      );
      await tester.ensureVisible(find.text('Tapo Strip').first);
      await tester.tap(find.text('Tapo Strip').first);
      await tester.pumpAndSettle();
      final slider = find.descendant(
        of: find.byKey(const ValueKey('detail-brightness')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.tapAt(tester.getCenter(slider) + const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appControllerProvider)
            .lights['light.tapo_strip']!
            .brightnessPercent,
        greaterThan(50),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('color-Red')));
      await tester.tap(find.byKey(const ValueKey('color-Red')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appControllerProvider)
            .lights['light.tapo_strip']!
            .rgbColor!
            .toJson(),
        [255, 0, 0],
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scenes').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('scene-movie')));
      await tester.tap(find.byKey(const ValueKey('scene-movie')));
      await tester.pumpAndSettle();
      final lights = container.read(appControllerProvider).lights;
      expect(lights['light.wipro_tube_1']!.isOn, false);
      expect(lights['light.wipro_tube_2']!.isOn, false);
      expect(lights['light.tapo_strip']!.isOn, true);
      expect(lights['light.tapo_strip']!.brightnessPercent, 15);
      expect(lights['light.tapo_strip']!.rgbColor!.toJson(), [90, 30, 255]);
      expect(tester.takeException(), isNull);
    },
  );
}
