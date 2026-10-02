import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/demo_lights.dart';

import 'support.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(1440, 1100)]) {
    testWidgets(
      'timer creation, cancellation, validation and clock time at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = DemoLights(latency: Duration.zero);
        final container = testContainer(
          backend: backend,
          settings: MemorySettings(
            const AppSettings(demo: true, theme: ThemeMode.dark),
          ),
        );
        addTearDown(container.dispose);
        await tester.runAsync(() async {
          final font = FontLoader('Inter');
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
            font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
          }
          await font.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
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
        Future<void> reveal(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
        }

        final entry = find.byKey(const ValueKey('room-timers'));
        await reveal(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        Future<void> capture(String name) async {
          if (!const bool.fromEnvironment('SMARTLIGHT_CAPTURE_UI')) return;
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/ui-review/${size.width.toInt()}-timers-$name.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('editor');
        final minutes = find.byKey(const ValueKey('timer-minutes'));
        final save = find.byKey(const ValueKey('set-timer'));
        await reveal(minutes);
        await tester.enterText(minutes, '0');
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await tester.enterText(minutes, '1441');
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await tester.enterText(minutes, '30');
        await tester.pumpAndSettle();
        await reveal(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Cancel timer'), findsNWidgets(3));
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await capture('active');
        final cancel = find.byKey(const ValueKey('cancel-timer-tube1'));
        await reveal(cancel);
        await tester.pumpAndSettle();
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.text('Cancel timer'), findsNWidgets(2));
        expect(find.text('1 light timer cancelled.'), findsOneWidget);
        await reveal(find.text('At a time'));
        await tester.tap(find.text('At a time'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Runs once'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('choose-timer-time')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        final tube1 = find.byKey(const ValueKey('timer-light-tube1'));
        await reveal(tube1);
        await tester.tap(tube1);
        await tester.pumpAndSettle();
        await reveal(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Cancel timer'), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        // Close the screen; opening it again reads device timers rather than a
        // local schedule record. Merely closing a screen does not cancel a timer.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await reveal(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('Cancel timer'), findsNWidgets(3));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
