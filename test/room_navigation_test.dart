import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/screens/scenes/room_scenes_screen.dart';

import 'support.dart';

const reading = LightScene('custom-reading', 'Reading', '', {
  'tube1': LightCommand(brightnessPercent: 30),
});

class StoredSettings extends MemorySettings {
  StoredSettings(super.value);
  bool fail = false;
  @override
  Future<void> write(AppSettings settings) async {
    if (fail) throw StateError('Disk full');
    value = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
  }
}

void main() {
  test('room scene choices migrate, round trip, tolerate damage and retain other settings', () {
    final original = const AppSettings(
      demo: true,
      theme: ThemeMode.dark,
      customScenes: [reading],
    );
    final migrated = AppSettings.fromJson(original.toJson());
    expect(migrated.roomSceneIds, isNull);
    expect(AppState(settings: migrated).roomScenes.map((s) => s.id), [
      'custom-reading',
      'study',
      'movie',
      'chill',
    ]);
    final edited = AppSettings.fromJson(
      original.copyWith(roomSceneIds: ['sleep', 'custom-reading']).toJson(),
    );
    expect(AppState(settings: edited).roomScenes.map((s) => s.id), [
      'sleep',
      'custom-reading',
    ]);
    expect(edited.theme, original.theme);
    expect(edited.customScenes.single.toJson(), reading.toJson());
    expect(
      edited.slots.map((s) => s.toJson()),
      original.slots.map((s) => s.toJson()),
    );
    expect(
      AppState(
        settings: AppSettings.fromJson(
          edited.copyWith(roomSceneIds: []).toJson(),
        ),
      ).roomScenes,
      isEmpty,
    );
    final damaged = AppSettings.fromJson({
      ...original.toJson(),
      'roomSceneIds': [null, 42, 'movie', 'movie', 'bogus', 'custom-deleted'],
    });
    expect(AppState(settings: damaged).roomScenes.map((s) => s.id), ['movie']);
    expect(damaged.customScenes.single.id, reading.id);
  });

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    StoredSettings? store,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = testContainer(
      settings:
          store ??
          StoredSettings(
            const AppSettings(demo: true, customScenes: [reading]),
          ),
    );
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

  for (final size in [const Size(360, 800), const Size(1440, 1000)]) {
    testWidgets('swipes, navigation buttons and slider gestures at $size', (
      tester,
    ) async {
      final container = await launch(tester, size: size);
      final pages = find.byKey(const ValueKey('main-pages'));
      int selected() =>
          tester.widget<PageView>(pages).controller!.page!.round();
      await tester.dragFrom(
        tester.getTopLeft(pages) +
            Offset(tester.getSize(pages).width * .85, 60),
        Offset(-tester.getSize(pages).width * .75, 0),
      );
      await tester.pumpAndSettle();
      expect(selected(), 1);
      expect(find.text('All scenes'), findsOneWidget);
      await tester.dragFrom(
        tester.getTopLeft(pages) +
            Offset(tester.getSize(pages).width * .85, 60),
        Offset(-tester.getSize(pages).width * .75, 0),
      );
      await tester.pumpAndSettle();
      expect(selected(), 2);
      expect(find.text('Connected lights'), findsOneWidget);
      if (size.width < 850) {
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
      }
      await tester.dragFrom(
        tester.getTopLeft(pages) +
            Offset(tester.getSize(pages).width * .15, 60),
        Offset(tester.getSize(pages).width * .75, 0),
      );
      await tester.pumpAndSettle();
      expect(selected(), 1);
      await tester.tap(find.text('My room').first);
      await tester.pumpAndSettle();
      expect(selected(), 0);
      final slider = find.descendant(
        of: find.byKey(const ValueKey('master-brightness')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.drag(slider, const Offset(-50, 0));
      await tester.pumpAndSettle();
      expect(selected(), 0);
      expect(tester.takeException(), isNull);
      await container.read(appControllerProvider.notifier).setForeground(false);
    });
  }

  testWidgets(
    'room scene choices save, survive reopening, allow none, and do not delete scenes',
    (tester) async {
      final store = StoredSettings(
        const AppSettings(demo: true, customScenes: [reading]),
      );
      final container = await launch(tester, store: store);
      final edit = find.byKey(const ValueKey('edit-room-scenes'));
      await tester.ensureVisible(edit);
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const PageStorageKey('main-page-0')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('room-scene-sleep')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('room-scene-custom-reading')));
      await tester.tap(find.text('Save selection'));
      await tester.pumpAndSettle();
      expect(
        container.read(appControllerProvider).roomScenes.map((s) => s.id),
        ['sleep', 'custom-reading'],
      );
      expect(find.byKey(const ValueKey('scene-study')), findsNothing);
      expect(find.byKey(const ValueKey('scene-sleep')), findsOneWidget);
      expect(container.read(appControllerProvider).scenes.length, 5);
      expect(store.value.customScenes.single.id, reading.id);
      final roundTrip = AppSettings.fromJson(
        jsonDecode(jsonEncode(store.value.toJson())),
      );
      expect(roundTrip.roomSceneIds, ['sleep', 'custom-reading']);
      final offset = scroll.pixels;
      await tester.tap(find.text('Scenes').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-study')), findsOneWidget);
      await tester.tap(find.text('My room').first);
      await tester.pumpAndSettle();
      final restored = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const PageStorageKey('main-page-0')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      expect(restored, closeTo(offset, 2));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('room-scene-study')),
            )
            .value,
        false,
      );
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save selection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No scenes selected.'), findsOneWidget);
      expect(store.value.roomSceneIds, isEmpty);
      expect(tester.takeException(), isNull);
      await container.read(appControllerProvider.notifier).setForeground(false);
    },
  );

  testWidgets('scene picker cancel and failed saves preserve saved selection', (
    tester,
  ) async {
    final store = StoredSettings(
      const AppSettings(demo: true, customScenes: [reading]),
    );
    final container = await launch(tester, store: store);
    final edit = find.byKey(const ValueKey('edit-room-scenes'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear selection'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.value.roomSceneIds, isNull);
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear selection'));
    store.fail = true;
    await tester.tap(find.text('Save selection'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not save your room scenes'),
      findsOneWidget,
    );
    expect(find.byType(RoomScenesScreen), findsOneWidget);
    expect(container.read(appControllerProvider).settings.roomSceneIds, isNull);
    store.fail = false;
    await tester.tap(find.text('Save selection'));
    await tester.pumpAndSettle();
    expect(store.value.roomSceneIds, isEmpty);
    expect(tester.takeException(), isNull);
    await container.read(appControllerProvider.notifier).setForeground(false);
  });
}
