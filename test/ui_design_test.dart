import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';

import 'support.dart';

const goldenHour = LightScene(
  'custom-golden-hour',
  'Golden hour',
  'A warmer room. A slower evening.',
  {
    'tube1': LightCommand(brightnessPercent: 35, kelvin: 3200),
    'tube2': LightCommand(brightnessPercent: 35, kelvin: 3200),
    'strip': LightCommand(brightnessPercent: 20, kelvin: 3200),
  },
);

void main() {
  for (final size in [
    const Size(412, 915),
    const Size(1440, 1000),
    const Size(360, 800),
  ]) {
    testWidgets('Figma layouts and live card controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = testContainer(
        settings: MemorySettings(
          const AppSettings(
            theme: ThemeMode.dark,
            demo: true,
            customScenes: [goldenHour],
          ),
        ),
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        final font = FontLoader('Inter');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
        }
        await font.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await container.read(appControllerProvider.notifier).initialize();
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const SmartLightApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        final element = find.byType(Scaffold).first;
        if (element.evaluate().isNotEmpty) {
          ScaffoldMessenger.of(tester.element(element)).clearSnackBars();
          await tester.pumpAndSettle();
        }
        if (!const bool.fromEnvironment('SMARTLIGHT_CAPTURE_UI')) return;
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ui-review/${size.width.toInt()}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('room');
      final slider = find.descendant(
        of: find.byKey(const ValueKey('brightness-tube1')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.tapAt(tester.getCenter(slider));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appControllerProvider)
            .lights['light.wipro_tube_1']!
            .brightnessPercent,
        closeTo(50, 5),
      );
      await tester.tap(find.text('Scenes').first);
      await tester.pumpAndSettle();
      await capture('scenes');
      await tester.tap(find.text('My scenes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-study')), findsNothing);
      expect(
        find.byKey(const ValueKey('scene-custom-golden-hour')),
        findsOneWidget,
      );
      await tester.tap(find.text('Presets'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scene-custom-golden-hour')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('scene-study')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-scene')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scene-name')),
        'Golden hour',
      );
      await tester.pumpAndSettle();
      await capture('editor');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      await capture('settings');
      expect(find.text('Connection diagnostics'), findsOneWidget);
      await tester.tap(find.text('My room').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Wipro Tube 1'));
      await tester.tap(find.text('Wipro Tube 1'));
      await tester.pumpAndSettle();
      await capture('light');
      await tester.pageBack();
      await tester.pumpAndSettle();
    });
  }
}
