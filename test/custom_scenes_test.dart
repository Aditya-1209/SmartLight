import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/demo_lights.dart';
import 'package:smart_light/screens/scenes/scene_editor_screen.dart';
import 'package:smart_light/widgets/brightness_slider.dart';
import 'package:smart_light/services/device_exception.dart';

import 'support.dart';

const sample = LightScene('custom-reading', 'Reading', 'A quiet corner', {
  'tube1': LightCommand(brightnessPercent: 38, kelvin: 3000),
  'strip': LightCommand(on: false),
}, appearance: 'study');

class GuardedCredentials extends MemoryCredentials {
  int writes = 0;
  bool locked = false;
  @override
  Future<ConnectionConfig?> read() async {
    if (locked) throw Exception('Locked');
    return super.read();
  }

  @override
  Future<void> write(ConnectionConfig value) async {
    writes++;
    await super.write(value);
  }
}

class DurableSettings extends MemorySettings {
  bool fail = false;
  DurableSettings([super.value]);
  @override
  Future<void> write(AppSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    if (fail) throw Exception('Disk full');
    value = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
  }
}

class OfflineConfigured extends ConfiguredDemo {
  OfflineConfigured(super.config);
  @override
  Future<LightEntity> getLight(String id) async => LightEntity(
    entityId: id,
    friendlyName: 'Offline fixture',
    state: 'unavailable',
    attributes: {},
  );
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      450,
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
}

void main() {
  test(
    'old preferences migrate without changing theme, demo or device mappings',
    () {
      final old = {
        'theme': 'dark',
        'demo': true,
        'slots': [
          {'id': 'tube1', 'name': 'Desk', 'entityId': 'light.desk'},
        ],
      };
      final settings = AppSettings.fromJson(old);
      expect(settings.customScenes, isEmpty);
      expect(settings.theme, ThemeMode.dark);
      expect(settings.demo, true);
      expect(settings.slots.first.name, 'Desk');
      expect(settings.slots.first.entityId, 'light.desk');
      final restored = AppSettings.fromJson(
        settings.copyWith(customScenes: [sample]).toJson(),
      );
      expect(restored.slots.first.toJson(), settings.slots.first.toJson());
      expect(restored.customScenes.single.toJson(), sample.toJson());
    },
  );

  test(
    'corrupt scenes are isolated and invalid control values cannot be loaded',
    () {
      for (final bad in [
        {'on': true, 'brightness': -1},
        {'on': true, 'brightness': double.nan},
        {'on': true, 'kelvin': 300},
        {
          'on': true,
          'rgb': [0, 256, 3],
        },
        {
          'on': true,
          'rgb': [0, 0, 0],
          'kelvin': 3000,
        },
        {'on': 'yes'},
      ]) {
        expect(
          () => LightScene.fromJson({
            ...sample.toJson(),
            'commands': {'tube1': bad},
          }),
          throwsFormatException,
        );
      }
      final settings = AppSettings.fromJson({
        'theme': 'dark',
        'customScenes': [
          null,
          {'id': 'bad'},
          sample.toJson(),
          sample.toJson(),
        ],
      });
      expect(settings.theme, ThemeMode.dark);
      expect(settings.customScenes.single.name, 'Reading');
    },
  );

  test('capture honors the active color mode and off state', () {
    LightEntity light(String state, String mode) => LightEntity(
      entityId: 'light.fixture',
      friendlyName: 'Fixture',
      state: state,
      attributes: {
        'brightness': 102,
        'rgb_color': [100, 20, 255],
        'color_temp_kelvin': 3100,
        'color_mode': mode,
        'supported_color_modes': ['rgb', 'color_temp'],
      },
    );
    final white = LightScene.capture(light('on', 'color_temp'));
    expect(white.brightnessPercent, 40);
    expect(white.kelvin, 3100);
    expect(white.rgb, isNull);
    final color = LightScene.capture(light('on', 'rgb'));
    expect(color.rgb!.toJson(), [100, 20, 255]);
    expect(color.kelvin, isNull);
    final off = LightScene.capture(light('off', 'rgb'));
    expect(off.on, false);
    expect(off.rgb, isNull);
    expect(off.brightnessPercent, isNull);
  });

  test('concurrent scene/theme saves survive restart without any credential writes', () async {
    final credentials = GuardedCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final before = jsonEncode(credentials.config!.toJson());
    final settings = DurableSettings(const AppSettings(demo: true));
    var container = testContainer(credentials: credentials, settings: settings);
    var controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    await Future.wait([
      controller.saveScene(sample),
      controller.setTheme(ThemeMode.dark),
      controller.saveScene(
        const LightScene('custom-second', 'Another', '', {
          'strip': LightCommand(on: false),
        }),
      ),
    ]);
    expect(settings.value.customScenes.length, 2);
    expect(settings.value.theme, ThemeMode.dark);
    expect(credentials.writes, 0);
    expect(jsonEncode(credentials.config!.toJson()), before);
    container.dispose();
    container = testContainer(credentials: credentials, settings: settings);
    addTearDown(container.dispose);
    controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(
      container.read(appControllerProvider).settings.customScenes.length,
      2,
    );
    await controller.setDemo(false);
    await controller.saveDevice(tapoConfig(name: 'Still here'));
    expect(settings.value.customScenes.length, 2);
    expect(credentials.config!.devices.single.password, 'test-password');
    expect(
      jsonEncode(settings.value.toJson()),
      isNot(contains('test-password')),
    );
  });

  test('saving is inert; applying affects only selected slots; edit/delete/restore persist', () async {
    final settings = DurableSettings(const AppSettings(demo: true));
    final container = testContainer(settings: settings);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    final before = container.read(appControllerProvider).lights;
    await controller.saveScene(sample);
    expect(container.read(appControllerProvider).lights, before);
    await controller.applyScene(sample);
    final lights = container.read(appControllerProvider).lights;
    expect(lights['light.wipro_tube_1']!.brightnessPercent, 38);
    expect(lights['light.wipro_tube_1']!.colorTempKelvin, 3000);
    expect(lights['light.tapo_strip']!.isOn, false);
    expect(lights['light.wipro_tube_2'], same(before['light.wipro_tube_2']));
    await controller.saveScene(
      LightScene(sample.id, 'Renamed', '', sample.commands),
    );
    expect(settings.value.customScenes.single.name, 'Renamed');
    await controller.deleteScene(sample.id);
    expect(settings.value.customScenes, isEmpty);
    await controller.saveScene(sample);
    expect(settings.value.customScenes.single.name, 'Reading');
  });

  test(
    'failed scene save and locked storage preserve all previous data',
    () async {
      final settings = DurableSettings(
        const AppSettings(demo: true, customScenes: [sample]),
      );
      final credentials = GuardedCredentials()
        ..config = ConnectionConfig([tapoConfig()]);
      var container = testContainer(
        settings: settings,
        credentials: credentials,
      );
      var controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      settings.fail = true;
      await expectLater(
        controller.deleteScene(sample.id),
        throwsA(isA<DeviceException>()),
      );
      expect(
        container.read(appControllerProvider).settings.customScenes.single.name,
        'Reading',
      );
      expect(settings.value.customScenes.single.name, 'Reading');
      expect(credentials.writes, 0);
      container.dispose();
      credentials.locked = true;
      settings.fail = false;
      container = testContainer(settings: settings, credentials: credentials);
      addTearDown(container.dispose);
      controller = container.read(appControllerProvider.notifier);
      await expectLater(
        controller.saveScene(sample),
        throwsA(isA<DeviceException>()),
      );
      expect(settings.value.customScenes.single.name, 'Reading');
      expect(credentials.writes, 0);
    },
  );

  testWidgets('offline placeholders retain brightness and color editing', (
    tester,
  ) async {
    final config = ConnectionConfig([tapoConfig()]);
    final credentials = MemoryCredentials()..config = config;
    final container = testContainer(
      demo: false,
      credentials: credentials,
      backend: OfflineConfigured(config),
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SceneEditorScreen(
            scene: LightScene('custom-offline', 'Offline scene', '', {
              'strip': LightCommand(brightnessPercent: 35, kelvin: 3000),
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('scene-mode-strip-white')));
    final modes = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('scene-mode-strip-white')),
    );
    // The color option must be usable even when no capabilities were returned.
    await tester.tap(find.byKey(const ValueKey('scene-mode-strip-white')));
    await tester.pumpAndSettle();
    expect(find.text('Color'), findsOneWidget);
    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    expect(modes.enabled, true);
    expect(
      find.byWidgetPredicate(
        (w) => w is ValueSlider && w.label == 'Brightness',
      ),
      findsOneWidget,
    );
    await reveal(tester, find.text('Scene color'));
    expect(find.text('Scene color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(1280, 800),
    const Size(1920, 1080),
  ]) {
    testWidgets('create, capture, edit, duplicate and undo scene at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = DemoLights(latency: Duration.zero);
      final container = testContainer(backend: backend);
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SmartLightApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scenes').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-scene')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scene-name')),
        'Evening reading',
      );
      await reveal(tester, find.byKey(const ValueKey('capture-scene')));
      await tester.tap(find.byKey(const ValueKey('capture-scene')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('scene-power-tube1')));
      await tester.tap(find.byKey(const ValueKey('scene-power-tube1')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('include-tube2')));
      await tester.tap(find.byKey(const ValueKey('include-tube2')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('save-scene')));
      await tester.tap(find.byKey(const ValueKey('save-scene')));
      await tester.pumpAndSettle();
      var scene = container
          .read(appControllerProvider)
          .settings
          .customScenes
          .single;
      expect(scene.commands.keys, ['tube1', 'strip']);
      expect(scene.commands['tube1']!.on, false);
      expect(
        container
            .read(appControllerProvider)
            .lights['light.wipro_tube_1']!
            .isOn,
        true,
      );
      await reveal(tester, find.byKey(ValueKey('scene-${scene.id}')));
      await tester.tap(find.byKey(ValueKey('scene-${scene.id}')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appControllerProvider)
            .lights['light.wipro_tube_1']!
            .isOn,
        false,
      );
      expect(
        container
            .read(appControllerProvider)
            .lights['light.wipro_tube_2']!
            .isOn,
        true,
      );
      await tester.tap(find.byTooltip('Options for Evening reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit scene'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scene-name')),
        'Evening calm',
      );
      await reveal(tester, find.byKey(const ValueKey('save-scene')));
      await tester.tap(find.byKey(const ValueKey('save-scene')));
      await tester.pumpAndSettle();
      scene = container
          .read(appControllerProvider)
          .settings
          .customScenes
          .single;
      expect(scene.name, 'Evening calm');
      await reveal(tester, find.byTooltip('Options for Evening calm'));
      await tester.tap(find.byTooltip('Options for Evening calm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate scene'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('save-scene')));
      await tester.tap(find.byKey(const ValueKey('save-scene')));
      await tester.pumpAndSettle();
      expect(
        container.read(appControllerProvider).settings.customScenes.length,
        2,
      );
      await reveal(tester, find.byTooltip('Options for Evening calm copy'));
      await tester.tap(find.byTooltip('Options for Evening calm copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete scene'));
      await tester.pumpAndSettle();
      expect(
        container.read(appControllerProvider).settings.customScenes.length,
        1,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        container.read(appControllerProvider).settings.customScenes.length,
        2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
