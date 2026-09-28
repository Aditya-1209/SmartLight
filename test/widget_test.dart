import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/providers/app_controller.dart';

import 'support.dart';

void main() {
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    bool demo = true,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = testContainer(demo: demo);
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
    return container;
  }

  testWidgets('dashboard has three cards and power changes state', (
    tester,
  ) async {
    final container = await launch(tester);
    for (final slot in ['tube1', 'tube2', 'strip']) {
      expect(find.byKey(ValueKey('device-$slot')), findsOneWidget);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('power-tube1')));
    await tester.tap(find.byKey(const ValueKey('power-tube1')));
    await tester.pumpAndSettle();
    expect(
      container.read(appControllerProvider).lights['light.wipro_tube_1']!.isOn,
      false,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'setup, settings and diagnostics render without credentials leaking',
    (tester) async {
      await launch(tester, demo: false);
      expect(find.text('One room. All your lights.'), findsOneWidget);
      await tester.tap(find.text('Add your lights'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strip-host')), findsOneWidget);
      expect(find.byKey(const ValueKey('strip-password')), findsOneWidget);
      await tester.ensureVisible(find.text('Test connection'));
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter the light’s local IPv4'),
        findsOneWidget,
      );
      await tester.tap(find.text('Diagnostics').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Refreshes every 5 seconds while the app is open.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ha-token')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('scene interaction and offline banner', (tester) async {
    final container = await launch(tester);
    await tester.tap(find.text('Scenes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-movie')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(appControllerProvider)
          .lights['light.tapo_strip']!
          .brightnessPercent,
      15,
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).setDemoOffline(true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room Wi-Fi offline (demo).'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(412, 915),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('responsive layout ${size.width}x${size.height}', (
      tester,
    ) async {
      await launch(tester, size: size);
      expect(
        find.byType(NavigationBar),
        size.width < 850 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
