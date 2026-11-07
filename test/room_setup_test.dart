import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/device_slot.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/screens/settings/settings_screen.dart';
import 'package:smart_light/widgets/room_preview.dart';

import 'support.dart';

class PersistentSettings extends MemorySettings {
  PersistentSettings(super.value);
  bool fail = false;
  @override
  Future<void> write(AppSettings settings) async {
    if (fail) throw StateError('Storage unavailable');
    value = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
  }
}

void main() {
  test('old rooms retain personal preview and new installs use original illustration', () {
    expect(const AppSettings().genericRoomPreview, isTrue);
    final legacy = AppSettings.fromJson({'theme': 'dark'});
    expect(legacy.genericRoomPreview, isFalse);
    expect(legacy.slots.length, 3);
    final empty = AppSettings.fromJson(const AppSettings(slots: []).toJson());
    expect(empty.slots, isEmpty);
    expect(empty.genericRoomPreview, isTrue);
    final repaired = AppSettings.fromJson({
      'slots': [
        {'id': 'unknown', 'name': 'Unknown'},
        {'id': 'tube2', 'name': 'Desk'},
        {'id': 'tube2', 'name': 'Duplicate'},
      ],
    });
    expect(repaired.slots.map((s) => s.name), ['Desk']);
  });

  test('delete saved or unconfigured cards, survive restart, add named replacements and import', () async {
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final settings = PersistentSettings(
      const AppSettings(theme: ThemeMode.dark),
    );
    var container = testContainer(
      demo: false,
      credentials: credentials,
      settings: settings,
    );
    var controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    for (final id in ['tube1', 'tube2', 'strip']) {
      await controller.deleteLight(id);
    }
    expect(container.read(appControllerProvider).slots, isEmpty);
    expect(container.read(appControllerProvider).configured, isFalse);
    expect(credentials.config!.devices, isEmpty);
    expect(settings.value.theme, ThemeMode.dark);
    expect(
      container.read(appControllerProvider).scenes.length,
      LightScene.defaults.length,
    );
    container.dispose();
    container = testContainer(
      demo: false,
      credentials: credentials,
      settings: settings,
    );
    addTearDown(container.dispose);
    controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(container.read(appControllerProvider).slots, isEmpty);
    await controller.addLight('  Bedroom  ');
    await controller.addLight('Desk');
    expect(container.read(appControllerProvider).slots.map((s) => s.name), [
      'Bedroom',
      'Desk',
    ]);
    expect(credentials.config!.devices, isEmpty);
    await controller.importConnections(
      ConnectionConfig([tapoConfig(name: 'New strip')]),
    );
    expect(container.read(appControllerProvider).slots.map((s) => s.name), [
      'Bedroom',
      'Desk',
      'New strip',
    ]);
    expect(credentials.config!.devices.single.password, 'test-password');
    await expectLater(controller.addLight('Fourth'), throwsException);
    await controller.setGenericRoomPreview(false);
    expect(settings.value.genericRoomPreview, isFalse);
  });

  test(
    'failed deletion restores secure credentials and retains room cards',
    () async {
      final credentials = MemoryCredentials()
        ..config = ConnectionConfig([tapoConfig()]);
      final settings = PersistentSettings(const AppSettings())..fail = true;
      final container = testContainer(
        demo: false,
        credentials: credentials,
        settings: settings,
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      await expectLater(controller.deleteLight('strip'), throwsException);
      expect(credentials.config!.devices.single.password, 'test-password');
      expect(container.read(appControllerProvider).slots.length, 3);
      expect(settings.value.slots, DeviceSlot.defaults);
    },
  );

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets('delete confirmation, empty state, named add at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = PersistentSettings(const AppSettings());
      final container = testContainer(demo: false, settings: settings);
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(appControllerProvider.notifier).initialize(),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ConnectedLightsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> press(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await press(find.byKey(const ValueKey('delete-light-tube1')));
      await press(find.text('Cancel'));
      expect(container.read(appControllerProvider).slots.length, 3);
      for (final id in ['tube1', 'tube2', 'strip']) {
        await press(find.byKey(ValueKey('delete-light-$id')));
        await press(find.widgetWithText(FilledButton, 'Delete'));
      }
      expect(find.byType(DeviceSetupCard), findsNothing);
      expect(
        find.text('No lights yet. Add a light to set up this room.'),
        findsOneWidget,
      );
      await press(find.byKey(const ValueKey('add-light')));
      await press(find.widgetWithText(FilledButton, 'Add'));
      expect(find.text('Enter a name for your light.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Bedroom lamp');
      await press(find.widgetWithText(FilledButton, 'Add'));
      expect(
        container.read(appControllerProvider).slots.single.name,
        'Bedroom lamp',
      );
      expect(find.text('Bedroom lamp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('generic illustration bypasses personal image provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RoomIllustration(height: 200, generic: true)),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Generic room illustration'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-room-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
