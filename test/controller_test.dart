import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/device_slot.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/services/demo_lights.dart';

import 'support.dart';

void main() {
  test(
    'master control identifies each failed device and updates successful ones',
    () async {
      final backend = DemoLights(latency: Duration.zero)
        ..failCommands.add('light.wipro_tube_2');
      final container = testContainer(backend: backend);
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      final report = await controller.controlAll(const LightCommand(on: false));
      expect(report.succeeded, containsAll(['Wipro Tube 1', 'Tapo Strip']));
      expect(report.failed.keys, ['Wipro Tube 2']);
      expect(report.message, contains('Wipro Tube 2'));
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
      expect(container.read(appControllerProvider).busy, isEmpty);
    },
  );
  test('unavailable device does not stop a scene', () async {
    final backend = DemoLights(latency: Duration.zero);
    backend.setAvailable('light.wipro_tube_2', false);
    final container = testContainer(backend: backend);
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    final report = await controller.applyScene(LightScene.defaults.first);
    expect(report.succeeded.length, 2);
    expect(report.failed['Wipro Tube 2'], 'Unavailable.');
  });
  test('offline refresh retains state, reports error, and recovers', () async {
    final container = testContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    final previous = container.read(appControllerProvider).lastRefresh;
    await controller.setDemoOffline(true);
    expect(container.read(appControllerProvider).connected, false);
    expect(container.read(appControllerProvider).lights.length, 3);
    expect(container.read(appControllerProvider).lastRefresh, previous);
    await controller.setDemoOffline(false);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(container.read(appControllerProvider).connected, true);
    expect(container.read(appControllerProvider).error, null);
  });
  test('demo toggle preserves real credentials, mappings and theme through restart', () async {
    final credentials = MemoryCredentials()
      ..config = ConnectionConfig([tapoConfig()]);
    final settings = MemorySettings(const AppSettings(slots: DeviceSlot.demo));
    var container = testContainer(
      demo: false,
      credentials: credentials,
      settings: settings,
    );
    var controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(container.read(appControllerProvider).settings.demo, false);
    await controller.setTheme(ThemeMode.dark);
    await controller.setDemo(true);
    await controller.setDemo(false);
    expect(credentials.config!.devices.single.password, 'test-password');
    expect(settings.value.slots, DeviceSlot.demo);
    container.dispose();
    container = testContainer(credentials: credentials, settings: settings);
    addTearDown(container.dispose);
    controller = container.read(appControllerProvider.notifier);
    await controller.initialize();
    expect(
      container.read(appControllerProvider).settings.theme,
      ThemeMode.dark,
    );
    expect(container.read(appControllerProvider).settings.demo, false);
  });
  test(
    'saving one light works without the other two and secures credentials',
    () async {
      final credentials = MemoryCredentials();
      final settings = MemorySettings();
      final container = testContainer(
        demo: false,
        credentials: credentials,
        settings: settings,
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      await controller.saveDevice(tapoConfig());
      expect(credentials.config!.devices.single.password, 'test-password');
      expect(
        settings.value.toJson().toString(),
        isNot(contains('test-password')),
      );
      expect(container.read(appControllerProvider).connected, true);
    },
  );
  test('corrupt preferences recover with safe defaults', () {
    final settings = AppSettings.fromJson({
      'slots': [
        null,
        {'id': 'tube1', 'name': 123, 'entityId': 'sensor.invalid'},
      ],
      'theme': 'invalid',
    });
    expect(settings.slots.first.entityId, null);
    expect(settings.theme, ThemeMode.system);
  });
}
