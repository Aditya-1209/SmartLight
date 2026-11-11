import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/screens/scenes/scenes_screen.dart';
import 'package:smart_light/services/demo_lights.dart';

import 'support.dart';

const editedSleep = LightScene(
  'sleep',
  'Night preset',
  'Dim, then off',
  {'strip': LightCommand(brightnessPercent: 4, rgb: RgbColor(255, 40, 10))},
  appearance: 'sparkle',
  turnOff: SceneOffSchedule.after(15),
);

class PresetStore extends MemorySettings {
  PresetStore(super.value);
  bool fail = false;
  @override
  Future<void> write(AppSettings settings) async {
    if (fail) throw StateError('Storage failed');
    value = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
  }
}

class PresetBackend extends DemoLights {
  PresetBackend() : super(latency: Duration.zero);
  int commands = 0;
  @override
  Future<void> command(LightEntity light, LightCommand command) async {
    commands++;
    return super.command(light, command);
  }
}

void main() {
  test('preset migration, overrides and deletions round trip; damaged/cross-category data is isolated', () {
    final old = AppSettings.fromJson({'theme': 'dark'});
    expect(AppState(settings: old).presetScenes.map((s) => s.id), [
      'study',
      'movie',
      'chill',
      'sleep',
    ]);
    final saved = AppSettings.fromJson(
      const AppSettings(
        presetScenes: [editedSleep],
        deletedPresetIds: ['movie'],
        roomSceneIds: ['sleep', 'movie'],
      ).toJson(),
    );
    final state = AppState(settings: saved);
    expect(state.roomScenes.single.toJson(), editedSleep.toJson());
    expect(
      state.presetScenes.where((s) => s.id == 'sleep').single.style,
      'sparkle',
    );
    expect(saved.customScenes, isEmpty);
    expect(state.presetScenes.map((s) => s.id), ['study', 'chill', 'sleep']);
    final damaged = AppSettings.fromJson({
      'customScenes': [editedSleep.toJson()],
      'presetScenes': [
        null,
        {'id': 'movie'},
        editedSleep.toJson(),
        editedSleep.toJson(),
        {
          'id': 'custom-cross',
          'name': 'Ignore',
          'commands': {
            'strip': {'on': true},
          },
        },
      ],
      'deletedPresetIds': [false, 'sleep', 'sleep', 'unknown'],
    });
    expect(damaged.customScenes, isEmpty);
    expect(damaged.presetScenes.single.toJson(), editedSleep.toJson());
    expect(damaged.deletedPresetIds, ['sleep']);
    expect(
      () => LightScene.fromJson({...editedSleep.toJson(), 'id': 'unknown'}),
      throwsFormatException,
    );
  });

  test('edit in place updates room shortcut; delete, undo and restore survive restart without commands', () async {
    final store = PresetStore(
      const AppSettings(demo: true, roomSceneIds: ['sleep', 'movie']),
    );
    final backend = PresetBackend();
    var container = testContainer(settings: store, backend: backend);
    var controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    await controller.saveScene(editedSleep);
    expect(store.value.customScenes, isEmpty);
    expect(
      container.read(appControllerProvider).roomScenes.first.name,
      'Night preset',
    );
    expect(
      container.read(appControllerProvider).roomScenes.first.turnOff!.minutes,
      15,
    );
    await controller.deleteScene('sleep');
    expect(container.read(appControllerProvider).roomScenes.map((s) => s.id), [
      'movie',
    ]);
    expect(backend.commands, 0);
    container.dispose();
    container = testContainer(settings: store);
    addTearDown(container.dispose);
    controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(
      container.read(appControllerProvider).scenes.any((s) => s.id == 'sleep'),
      false,
    );
    await controller.saveScene(
      editedSleep,
    ); // Undo restores the edited version.
    expect(
      container.read(appControllerProvider).roomScenes.first.toJson(),
      editedSleep.toJson(),
    );
    for (final id in LightScene.presetIds) {
      await controller.deleteScene(id);
    }
    expect(container.read(appControllerProvider).scenes, isEmpty);
    expect(container.read(appControllerProvider).roomScenes, isEmpty);
    await controller.restoreDeletedPresets();
    expect(container.read(appControllerProvider).presetScenes.length, 4);
    expect(
      container.read(appControllerProvider).roomScenes.first.toJson(),
      editedSleep.toJson(),
    );
    expect(store.value.theme, ThemeMode.system);
  });

  test('failed preset writes retain prior data and presets do not consume the custom scene quota', () async {
    final custom = List.generate(
      LightScene.maxCustomScenes,
      (i) => LightScene('custom-$i', 'Scene $i', '', {
        'strip': const LightCommand(),
      }),
    );
    final store = PresetStore(AppSettings(demo: true, customScenes: custom));
    final container = testContainer(settings: store);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    await controller.saveScene(editedSleep);
    expect(store.value.customScenes.length, LightScene.maxCustomScenes);
    store.fail = true;
    await expectLater(controller.deleteScene('sleep'), throwsException);
    expect(
      container.read(appControllerProvider).presetScenes.last.toJson(),
      editedSleep.toJson(),
    );
    expect(store.value.deletedPresetIds, isEmpty);
    await expectLater(
      controller.saveScene(LightScene.defaults.last),
      throwsException,
    );
    expect(store.value.presetScenes.single.toJson(), editedSleep.toJson());
  });

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets(
      'preset menus edit the original, delete/undo, handle no scenes and restore at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = PresetStore(const AppSettings(demo: true));
        final container = testContainer(settings: store);
        addTearDown(container.dispose);
        final controller = container.read(appControllerProvider.notifier);
        await tester.runAsync(controller.initialize);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: ScenesScreen()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              finder,
              400,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
          }
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tap(find.byTooltip('Options for Sleep'));
        await tap(find.text('Edit scene').last);
        expect(find.text('Edit scene').first, findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('scene-name')),
          'Night preset',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tap(find.text('After a delay'));
        await tester.enterText(
          find.byKey(const ValueKey('scene-off-minutes')),
          '15',
        );
        await tap(find.byKey(const ValueKey('save-scene')));
        await tap(find.byKey(const ValueKey('saved-scene-done')));
        expect(store.value.customScenes, isEmpty);
        expect(store.value.presetScenes.single.id, 'sleep');
        expect(store.value.presetScenes.single.turnOff!.minutes, 15);
        expect(find.byKey(const ValueKey('scene-sleep')), findsOneWidget);
        await tap(find.byTooltip('Options for Night preset'));
        await tap(find.text('Delete scene'));
        expect(find.byKey(const ValueKey('scene-sleep')), findsNothing);
        await tap(find.text('Undo'));
        expect(find.byKey(const ValueKey('scene-sleep')), findsOneWidget);
        expect(store.value.presetScenes.single.name, 'Night preset');
        for (final id in LightScene.presetIds) {
          await controller.deleteScene(id);
        }
        await tester.pumpAndSettle();
        expect(container.read(appControllerProvider).scenes, isEmpty);
        expect(
          find.text(
            'No presets. Create a scene or restore deleted presets below.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tap(find.byKey(const ValueKey('restore-presets')));
        expect(find.byKey(const ValueKey('scene-sleep')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
