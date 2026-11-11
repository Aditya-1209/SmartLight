import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/light_timer.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/repositories/settings_repository.dart';
import 'package:smart_light/screens/scenes/scene_editor_screen.dart';
import 'package:smart_light/services/demo_lights.dart';

import 'support.dart';

const timed = LightScene('custom-timed', 'Evening', 'Keep this description', {
  'tube1': LightCommand(brightnessPercent: 30),
  'strip': LightCommand(rgb: RgbColor(120, 30, 220)),
}, turnOff: SceneOffSchedule.after(30));

class SceneTimerBackend extends DemoLights {
  SceneTimerBackend() : super(latency: Duration.zero);
  final timers = <String, LightTimer>{};
  final events = <String>[];
  final unsupported = <String>{};
  final failRead = <String>{}, failSet = <String>{}, failCancel = <String>{};
  bool unconfirmedCancel = false, unconfirmedSet = false;
  Completer<void>? readGate, setGate, afterCommandGate;
  @override
  Future<void> command(LightEntity light, LightCommand command) async {
    events.add('command:${light.entityId}');
    await super.command(light, command);
    events.add('applied:${light.entityId}');
    await afterCommandGate?.future;
  }

  @override
  Future<LightTimerStatus> readTimer(String id) async {
    events.add('read:$id');
    if (failRead.contains(id)) throw StateError('Read failed');
    final light = await getLight(id);
    final result = LightTimerStatus(
      isOn: light.isOn,
      active: timers[id],
      togglesPower: !id.contains('tapo'),
      unsupportedReason: unsupported.contains(id)
          ? 'Native timer unsupported.'
          : null,
    );
    await readGate?.future;
    return result;
  }

  @override
  Future<LightTimerStatus> cancelTimer(String id) async {
    events.add('cancel:$id');
    if (failCancel.contains(id)) throw timerUnconfirmed;
    if (!unconfirmedCancel) timers.remove(id);
    return readTimer(id);
  }

  @override
  Future<LightTimerStatus> setTimer(
    String id,
    DateTime endsAt, {
    required bool on,
  }) async {
    events.add('set:$id');
    await setGate?.future;
    requireTimerAvailable(await readTimer(id), on);
    countdownSeconds(endsAt);
    timers[id] = LightTimer(id: 'native', endsAt: endsAt, on: on);
    if (failSet.contains(id)) throw timerUnconfirmed;
    return unconfirmedSet ? const LightTimerStatus(isOn: true) : readTimer(id);
  }
}

void main() {
  test('old scenes remain untimed; timing round-trips without changing commands or preferences', () {
    final old = timed.toJson()..remove('turnOff');
    expect(LightScene.fromJson(old).turnOff, isNull);
    final settings = AppSettings(
      theme: ThemeMode.dark,
      demo: true,
      customScenes: [timed],
      roomSceneIds: [timed.id],
      swapPreviewTubes: true,
    );
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())),
    );
    expect(restored.customScenes.single.toJson(), timed.toJson());
    expect(restored.customScenes.single.turnOff!.minutes, 30);
    expect(restored.theme, ThemeMode.dark);
    expect(restored.roomSceneIds, [timed.id]);
    expect(restored.swapPreviewTubes, true);
    final clock = LightScene.fromJson({
      ...timed.toJson(),
      'turnOff': {'mode': 'at', 'hour': 23, 'minute': 45},
    });
    expect(clock.turnOff!.hour, 23);
    expect(clock.turnOff!.minute, 45);
  });

  test('invalid schedules are rejected and clock recipes resolve on each application', () {
    for (final raw in [
      true,
      [],
      {},
      {'mode': 'x'},
      {'mode': 'after', 'minutes': 0},
      {'mode': 'after', 'minutes': 1441},
      {'mode': 'after', 'minutes': 1.5},
      {'mode': 'at', 'hour': 24, 'minute': 0},
      {'mode': 'at', 'hour': -1, 'minute': 0},
      {'mode': 'at', 'hour': 12, 'minute': 60},
      {'mode': 'at', 'hour': '12', 'minute': 30},
    ]) {
      expect(
        () => LightScene.fromJson({...timed.toJson(), 'turnOff': raw}),
        throwsFormatException,
      );
    }
    final now = DateTime(2026, 11, 6, 23, 50);
    expect(
      const SceneOffSchedule.after(30).resolve(now),
      now.add(const Duration(minutes: 30)),
    );
    expect(
      const SceneOffSchedule.at(23, 45).resolve(now),
      DateTime(2026, 11, 7, 23, 45),
    );
    expect(const SceneOffSchedule.at(0, 0).resolve(now), DateTime(2026, 11, 7));
  });

  Future<ProviderContainer> setup(
    SceneTimerBackend backend, {
    MemorySettings? settings,
  }) async {
    final container = testContainer(backend: backend, settings: settings);
    addTearDown(container.dispose);
    await container.read(appControllerProvider.notifier).initialize();
    return container;
  }

  test(
    'locking immediately after Sleep settings still arms the strip off timer',
    () async {
      final backend = SceneTimerBackend()..afterCommandGate = Completer<void>();
      final container = await setup(backend);
      final controller = container.read(appControllerProvider.notifier);
      final pending = controller.applyScene(
        const LightScene('custom-sleep', 'Sleep copy', '', {
          'tube1': LightCommand(on: false),
          'tube2': LightCommand(on: false),
          'strip': LightCommand(
            brightnessPercent: 5,
            rgb: RgbColor(255, 45, 15),
          ),
        }, turnOff: SceneOffSchedule.after(15)),
      );
      while (!backend.events.contains('applied:light.tapo_strip')) {
        await Future<void>.delayed(Duration.zero);
      }
      expect((await backend.getLight('light.tapo_strip')).isOn, isTrue);
      await controller.setForeground(false);
      backend.afterCommandGate!.complete();
      expect((await pending).hasFailures, isFalse);
      expect(backend.timers['light.tapo_strip']?.on, isFalse);
      expect(
        backend.timers['light.tapo_strip']!.endsAt
            .difference(DateTime.now())
            .inSeconds,
        inInclusiveRange(890, 900),
      );
      expect(container.read(appControllerProvider).connected, isFalse);
    },
  );

  test('saving is inert; applying arms only scene-on lights with one shared deadline', () async {
    final backend = SceneTimerBackend();
    final store = MemorySettings(const AppSettings(demo: true));
    final container = await setup(backend, settings: store);
    final controller = container.read(appControllerProvider.notifier);
    for (final slot
        in container
            .read(appControllerProvider)
            .slots
            .where((s) => timed.commands.containsKey(s.id))) {
      await controller.control(slot, const LightCommand(on: false));
    }
    backend.events.clear();
    await controller.saveScene(timed);
    expect(backend.events, isEmpty);
    final before = DateTime.now();
    final report = await controller.applyScene(timed);
    expect(report.hasFailures, false);
    expect(backend.timers.keys.toSet(), {
      'light.wipro_tube_1',
      'light.tapo_strip',
    });
    final deadline = backend.timers.values.first.endsAt;
    expect(
      backend.timers.values.every((t) => t.endsAt == deadline && !t.on),
      true,
    );
    expect(deadline.difference(before).inSeconds, inInclusiveRange(1799, 1802));
    expect(backend.events.where((e) => e.contains('tube_2')), isEmpty);
    expect(store.value.customScenes.single.turnOff!.minutes, 30);
    expect(container.read(appControllerProvider).busy, isEmpty);
  });

  test(
    'off/zero-brightness and excluded lights never receive scene timers',
    () async {
      final backend = SceneTimerBackend();
      final container = await setup(backend);
      final report = await container
          .read(appControllerProvider.notifier)
          .applyScene(
            const LightScene('custom-off', 'Off', '', {
              'tube1': LightCommand(on: false),
              'tube2': LightCommand(brightnessPercent: 0),
            }, turnOff: SceneOffSchedule.after(10)),
          );
      expect(report.hasFailures, false);
      expect(backend.timers, isEmpty);
      expect(
        backend.events.where(
          (e) => !e.startsWith('command:') && !e.startsWith('applied:'),
        ),
        isEmpty,
      );
    },
  );

  test('unsupported/read failures do not turn on a light; command and timer failures are reported per light', () async {
    for (final mode in [
      'unsupported',
      'read',
      'command',
      'timer',
      'unconfirmed',
    ]) {
      final backend = SceneTimerBackend();
      const id = 'light.wipro_tube_1';
      if (mode == 'unsupported') backend.unsupported.add(id);
      if (mode == 'read') backend.failRead.add(id);
      if (mode == 'command') backend.failCommands.add(id);
      if (mode == 'timer') backend.failSet.add(id);
      if (mode == 'unconfirmed') backend.unconfirmedSet = true;
      final container = await setup(backend);
      final report = await container
          .read(appControllerProvider.notifier)
          .applyScene(timed);
      expect(report.failed, contains('Wipro Tube 1'));
      if (mode == 'command') {
        expect(
          report.failed['Wipro Tube 1'],
          contains('Automatic turn-off was not set'),
        );
      }
      if (mode == 'unsupported' || mode == 'read') {
        expect(backend.events, isNot(contains('command:$id')));
      }
      if (mode == 'timer' || mode == 'unconfirmed') {
        expect(
          report.failed['Wipro Tube 1'],
          contains('Scene applied, but automatic turn-off was not confirmed'),
        );
        expect(backend.events.where((e) => e == 'set:$id').length, 1);
      } else {
        expect(backend.events, isNot(contains('set:$id')));
      }
      expect(container.read(appControllerProvider).busy, isEmpty);
    }
  });

  test('existing countdown is cancelled and confirmed before the scene; reapply starts a fresh deadline', () async {
    final backend = SceneTimerBackend();
    const id = 'light.wipro_tube_1';
    backend.timers[id] = LightTimer(
      id: 'old',
      endsAt: DateTime.now().add(const Duration(minutes: 5)),
      on: false,
    );
    final container = await setup(backend);
    final controller = container.read(appControllerProvider.notifier);
    final first = await controller.applyScene(timed);
    expect(first.hasFailures, false);
    expect(
      backend.events.indexOf('cancel:$id'),
      lessThan(backend.events.indexOf('command:$id')),
    );
    expect(
      backend.events.indexOf('command:$id'),
      lessThan(backend.events.indexOf('set:$id')),
    );
    backend.events.clear();
    expect((await controller.applyScene(timed)).hasFailures, false);
    expect(backend.events.where((e) => e == 'cancel:$id').length, 1);
    expect(backend.events.where((e) => e == 'set:$id').length, 1);
  });

  test(
    'unconfirmed cancellation stops before scene commands and is not retried',
    () async {
      for (final returnsActive in [false, true]) {
        final backend = SceneTimerBackend()..unconfirmedCancel = returnsActive;
        const id = 'light.wipro_tube_1';
        if (!returnsActive) backend.failCancel.add(id);
        backend.timers[id] = LightTimer(
          id: 'old',
          endsAt: DateTime.now().add(const Duration(minutes: 5)),
          on: false,
        );
        final container = await setup(backend);
        final report = await container
            .read(appControllerProvider.notifier)
            .applyScene(timed);
        expect(report.failed, contains('Wipro Tube 1'));
        expect(backend.events.where((e) => e == 'cancel:$id').length, 1);
        expect(backend.events, isNot(contains('command:$id')));
        expect(backend.events, isNot(contains('set:$id')));
      }
    },
  );

  test('busy spans scene plus timer writes; leaving foreground finishes the native handoff', () async {
    final backend = SceneTimerBackend()..setGate = Completer<void>();
    final container = await setup(backend);
    final controller = container.read(appControllerProvider.notifier);
    final pending = controller.applyScene(timed);
    while (!backend.events.any((e) => e.startsWith('set:'))) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(appControllerProvider).busy, isNotEmpty);
    expect((await controller.applyScene(timed)).hasFailures, true);
    expect((await controller.cancelLightTimer('tube1')).hasFailures, true);
    backend.setGate!.complete();
    expect((await pending).hasFailures, false);
    final other = SceneTimerBackend()..readGate = Completer<void>();
    final another = await setup(other);
    final c = another.read(appControllerProvider.notifier);
    final interrupted = c.applyScene(timed);
    while (other.events.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.setForeground(false);
    other.readGate!.complete();
    expect((await interrupted).hasFailures, false);
    expect(
      other.events.where(
        (e) => e.startsWith('command:') || e.startsWith('set:'),
      ),
      isNotEmpty,
    );
    expect(other.timers.length, 2);
    expect(another.read(appControllerProvider).connected, false);
  });

  test('background grace expires without late timer writes, and failure remains visible', () async {
    final backend = SceneTimerBackend()..afterCommandGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        credentialStoreProvider.overrideWithValue(MemoryCredentials()),
        settingsStoreProvider.overrideWithValue(
          MemorySettings(const AppSettings(demo: true)),
        ),
        backendFactoryProvider.overrideWithValue((config, demo) => backend),
        timerSetupGraceProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    addTearDown(container.dispose);
    final c = container.read(appControllerProvider.notifier);
    await c.initialize();
    final pending = c.applyScene(timed);
    while (!backend.events.any((e) => e.startsWith('applied:'))) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.setForeground(false);
    await c.setForeground(
      false,
    ); // hidden + paused must not reset the deadline.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(container.read(appControllerProvider).connected, false);
    expect(
      container.read(appControllerProvider).timerWarning,
      contains('interrupted'),
    );
    backend.afterCommandGate!.complete();
    expect((await pending).hasFailures, true);
    expect(backend.events.where((e) => e.startsWith('set:')), isEmpty);
    expect(container.read(appControllerProvider).timerWarning, isNotNull);
    c.dismissTimerWarning();
    expect(container.read(appControllerProvider).timerWarning, isNull);
  });

  test('resuming during handoff retains the operation; disposing always stops later writes', () async {
    final backend = SceneTimerBackend()..afterCommandGate = Completer<void>();
    final container = await setup(backend);
    final c = container.read(appControllerProvider.notifier);
    final pending = c.applyScene(timed);
    while (!backend.events.any((e) => e.startsWith('applied:'))) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.setForeground(false);
    await c.setForeground(true);
    backend.afterCommandGate!.complete();
    expect((await pending).hasFailures, false);
    expect(container.read(appControllerProvider).connected, true);
    final other = SceneTimerBackend()..afterCommandGate = Completer<void>();
    final disposed = testContainer(backend: other);
    final controller = disposed.read(appControllerProvider.notifier);
    await controller.initialize();
    final interrupted = controller.applyScene(timed);
    while (!other.events.any((e) => e.startsWith('applied:'))) {
      await Future<void>.delayed(Duration.zero);
    }
    disposed.dispose();
    other.afterCommandGate!.complete();
    expect((await interrupted).hasFailures, true);
    expect(other.events.where((e) => e.startsWith('set:')), isEmpty);
  });

  test(
    'untimed scenes do not inspect or alter timers through the timer API',
    () async {
      final backend = SceneTimerBackend();
      final container = await setup(backend);
      expect(
        (await container
                .read(appControllerProvider.notifier)
                .applyScene(
                  LightScene(timed.id, timed.name, '', timed.commands),
                ))
            .hasFailures,
        false,
      );
      expect(
        backend.events.every(
          (e) => e.startsWith('command:') || e.startsWith('applied:'),
        ),
        true,
      );
    },
  );

  test(
    'an invalid recipe performs no reads, commands or timer writes',
    () async {
      final backend = SceneTimerBackend();
      final container = await setup(backend);
      final report = await container
          .read(appControllerProvider.notifier)
          .applyScene(
            LightScene(
              timed.id,
              timed.name,
              '',
              timed.commands,
              turnOff: const SceneOffSchedule.after(0),
            ),
          );
      expect(report.hasFailures, true);
      expect(backend.events, isEmpty);
      expect(container.read(appControllerProvider).busy, isEmpty);
    },
  );

  for (final size in [const Size(360, 800), const Size(1280, 800)]) {
    testWidgets(
      'editor persists after/at/none and copies timing without activating it at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = SceneTimerBackend();
        final store = MemorySettings(const AppSettings(demo: true));
        final container = (await tester.runAsync(
          () => setup(backend, settings: store),
        ))!;
        Future<void> show({LightScene? scene, bool duplicate = false}) async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: SceneEditorScreen(scene: scene, duplicate: duplicate),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(scene: timed, duplicate: true);
        final minutes = find.byKey(const ValueKey('scene-off-minutes'));
        await tester.ensureVisible(minutes);
        await tester.pumpAndSettle();
        await tester.enterText(minutes, '0');
        await tester.tap(find.byKey(const ValueKey('save-scene')));
        await tester.pumpAndSettle();
        expect(find.text('Enter 1–1,440 minutes.'), findsOneWidget);
        expect(store.value.customScenes, isEmpty);
        await tester.ensureVisible(minutes);
        await tester.pumpAndSettle();
        await tester.enterText(minutes, '45');
        await tester.tap(find.byKey(const ValueKey('save-scene')));
        await tester.pumpAndSettle();
        final saved = store.value.customScenes.single;
        expect(saved.id, isNot(timed.id));
        expect(saved.turnOff!.minutes, 45);
        expect(backend.events, isEmpty);
        await show(scene: saved);
        await tester.ensureVisible(find.text('At a time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('At a time'));
        await tester.pumpAndSettle();
        final clock = find.byKey(const ValueKey('scene-off-time'));
        await tester.ensureVisible(clock);
        await tester.pumpAndSettle();
        await tester.tap(clock);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-scene')));
        await tester.pumpAndSettle();
        expect(store.value.customScenes.single.turnOff!.mode, SceneOffMode.at);
        await show(scene: store.value.customScenes.single);
        await tester.ensureVisible(find.text('None'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('None'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-scene')));
        await tester.pumpAndSettle();
        expect(store.value.customScenes.single.turnOff, isNull);
        expect(backend.events, isEmpty);
        expect(tester.takeException(), isNull);
        await container
            .read(appControllerProvider.notifier)
            .setForeground(false);
      },
    );
  }
}
