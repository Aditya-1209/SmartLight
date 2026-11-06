import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/app/app.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/providers/app_controller.dart';
import 'package:smart_light/widgets/room_preview.dart';

import 'support.dart';

LightEntity light({
  String state = 'on',
  String mode = 'rgb',
  List<int> rgb = const [255, 0, 0],
  int brightness = 255,
  int kelvin = 2700,
}) => LightEntity(
  entityId: 'light.fixture',
  friendlyName: 'Fixture',
  state: state,
  attributes: {
    'color_mode': mode,
    'rgb_color': rgb,
    'brightness': brightness,
    'color_temp_kelvin': kelvin,
  },
);

Future<ByteData> paintLighting(RoomLighting lighting) async {
  final recorder = ui.PictureRecorder();
  RoomLightingPainter(
    image: null,
    lighting: lighting,
  ).paint(Canvas(recorder), const Size(768, 512));
  final picture = recorder.endRecording();
  final image = await picture.toImage(768, 512);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return data;
}

List<int> pixel(ByteData data, int x, int y) =>
    List.generate(3, (i) => data.getUint8((y * 768 + x) * 4 + i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reported colour mode chooses RGB or white and never lights off/unavailable fixtures', () {
    expect(RoomLightStyle.fromLight(null), RoomLightStyle.unknown);
    expect(RoomLightStyle.fromLight(light(state: 'unavailable')).level, 0);
    expect(RoomLightStyle.fromLight(light(state: 'off')).level, 0);
    final rgb = RoomLightStyle.fromLight(
      light(rgb: [10, 20, 255], kelvin: 2700),
    );
    expect(rgb.color, const Color.fromARGB(255, 10, 20, 255));
    final warm = RoomLightStyle.fromLight(
      light(mode: 'color_temp', kelvin: 2700),
    );
    final cool = RoomLightStyle.fromLight(
      light(mode: 'color_temp', kelvin: 6500),
    );
    expect(warm.color.r, greaterThan(warm.color.b));
    expect(cool.color.b, greaterThan(cool.color.r));
  });

  test('brightness is bounded, linear and unchanged reports do not restart animations', () {
    final dim = RoomLightStyle.fromLight(light(brightness: 51));
    expect(dim.level, closeTo(.2, .01));
    expect(RoomLightStyle.fromLight(light(brightness: 0)).level, 0);
    expect(RoomLightStyle.fromLight(light(brightness: 999)).level, 1);
    final a = RoomLighting(tube1: dim);
    expect(
      a,
      RoomLighting(tube1: RoomLightStyle.fromLight(light(brightness: 51))),
    );
    final mid = RoomLighting.lerp(const RoomLighting(), a, .5);
    expect(mid.tube1.level, closeTo(.1, .01));
  });

  test('rendered pixels distinguish independent red/blue tubes and green side-strip glow', () async {
    final data = await paintLighting(
      const RoomLighting(
        tube1: RoomLightStyle(Colors.red, 1),
        tube2: RoomLightStyle(Colors.blue, 1),
        strip: RoomLightStyle(Colors.green, 1),
      ),
    );
    final left = pixel(data, 260, 83), right = pixel(data, 508, 71);
    expect(left[0], greaterThan(left[2] + 80));
    expect(right[2], greaterThan(right[0] + 80));
    for (final x in [149, 616]) {
      final side = pixel(data, x, 274);
      expect(side[1], greaterThan(side[0]));
      expect(side[1], greaterThan(side[2]));
    }
  });

  test(
    'black RGB does not create a white emitter or a coloured spill',
    () async {
      final off = await paintLighting(const RoomLighting());
      final black = await paintLighting(
        const RoomLighting(
          tube1: RoomLightStyle(Colors.black, 1),
          tube2: RoomLightStyle(Colors.black, 1),
          strip: RoomLightStyle(Colors.black, 1),
        ),
      );
      expect(black.buffer.asUint8List(), off.buffer.asUint8List());
    },
  );

  test('rendered lamp and panel brighten monotonically; switching one tube off leaves the other lit', () async {
    final off = await paintLighting(const RoomLighting());
    final dim = await paintLighting(
      const RoomLighting(tube1: RoomLightStyle(Colors.white, .2)),
    );
    final bright = await paintLighting(
      const RoomLighting(tube1: RoomLightStyle(Colors.white, 1)),
    );
    for (final point in [const Offset(260, 83), const Offset(260, 230)]) {
      final values = [
        off,
        dim,
        bright,
      ].map((d) => pixel(d, point.dx.toInt(), point.dy.toInt())[0]).toList();
      expect(values[1], greaterThan(values[0]));
      expect(values[2], greaterThan(values[1]));
    }
    final rightOnly = await paintLighting(
      const RoomLighting(tube2: RoomLightStyle(Colors.blue, 1)),
    );
    expect(pixel(rightOnly, 508, 71)[2], greaterThan(200));
    expect(pixel(rightOnly, 260, 83)[0], lessThan(pixel(bright, 260, 83)[0]));
  });

  testWidgets(
    'dashboard preview follows individual commands and scenes without sending extra commands',
    (tester) async {
      final container = testContainer();
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
      RoomLighting current() =>
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('live-room-preview')),
                      )
                      .painter!
                  as RoomLightingPainter)
              .lighting;
      final state = container.read(appControllerProvider);
      final controller = container.read(appControllerProvider.notifier);
      final first = state.slots.first;
      final second = state.slots[1];
      final initialRight = current().tube2;
      await tester.runAsync(
        () => controller.control(
          first,
          const LightCommand(rgb: RgbColor(255, 0, 0), brightnessPercent: 35),
        ),
      );
      await tester.pumpAndSettle();
      expect(current().tube1.color, const Color(0xffff0000));
      expect(current().tube1.level, closeTo(.35, .02));
      expect(current().tube2, initialRight);
      final originalLeft = current().tube1;
      await tester.runAsync(() => controller.setPreviewTubesSwapped(true));
      await tester.pumpAndSettle();
      expect(current().tube1, initialRight);
      expect(current().tube2, originalLeft);
      expect(
        (await container.read(settingsStoreProvider).read()).swapPreviewTubes,
        isTrue,
      );
      expect(
        container
            .read(appControllerProvider)
            .lightFor(first)!
            .rgbColor!
            .toJson(),
        [255, 0, 0],
      );
      await tester.runAsync(() => controller.setPreviewTubesSwapped(false));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => controller.control(first, const LightCommand(on: false)),
      );
      await tester.pumpAndSettle();
      expect(current().tube1.level, 0);
      expect(current().tube2.level, greaterThan(0));
      await tester.runAsync(
        () => controller.applyScene(
          container
              .read(appControllerProvider)
              .scenes
              .firstWhere((s) => s.id == 'movie'),
        ),
      );
      await tester.pumpAndSettle();
      expect(current().strip.level, closeTo(.15, .02));
      expect(current().strip.color, const Color.fromARGB(255, 90, 30, 255));
      expect(
        container.read(appControllerProvider).lightFor(second)!.available,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await controller.setForeground(false);
    },
  );
}
