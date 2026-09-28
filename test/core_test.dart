import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/models/device_slot.dart';
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/models/light_entity.dart';
import 'package:smart_light/models/scene.dart';
import 'package:smart_light/services/device_exception.dart';
import 'package:smart_light/services/demo_lights.dart';

void main() {
  test('brightness endpoints, clamping and all percentage round trips', () {
    expect(brightnessToPercent(0), 0);
    expect(brightnessToPercent(255), 100);
    expect(percentToBrightness(-10), 0);
    expect(percentToBrightness(120), 255);
    for (var i = 0; i <= 100; i++) {
      expect(brightnessToPercent(percentToBrightness(i)), i);
    }
  });
  test('malformed fields are safe and capabilities conservative', () {
    final light = LightEntity.fromJson({
      'attributes': {
        'brightness': 'bad',
        'rgb_color': [1],
        'color_temp': 0,
        'supported_color_modes': 5,
      },
    });
    expect(light.available, false);
    expect(light.brightness, null);
    expect(light.rgbColor, null);
    expect(light.colorTempKelvin, null);
    expect(light.supportsRgb, false);
    expect(light.supportsBrightness, false);
    expect(LightEntity.fromJson({'attributes': []}).state, 'unknown');
  });
  test('legacy temperature uses inverted mired limits', () {
    final light = LightEntity.fromJson({
      'attributes': {
        'color_temp': 250,
        'min_mireds': 153,
        'max_mireds': 500,
        'supported_features': 19,
      },
    });
    expect(light.colorTempKelvin, 4000);
    expect(light.minColorTempKelvin, 2000);
    expect(light.maxColorTempKelvin, 6536);
    expect(light.supportsRgb, true);
    expect(light.supportsTemperature, true);
  });
  test('configuration allows only local literal IPv4 and protects secrets', () {
    for (final host in [
      'example.com',
      'https://192.168.1.2',
      '8.8.8.8',
      '127.0.0.1',
      '192.168.1.2:80',
      '10.0.0.999',
    ]) {
      expect(
        () => DeviceConnection(
          slotId: 'strip',
          name: 'Strip',
          brand: DeviceBrand.tapo,
          host: host,
          email: 'a@example.com',
          password: 'secret',
        ),
        throwsA(isA<DeviceException>()),
      );
    }
    for (final host in [
      '192.168.1.2',
      '10.0.0.2',
      '172.16.0.2',
      '169.254.1.2',
    ]) {
      expect(DeviceConnection.isLocalAddress(host), true);
    }
  });
  test('mappings require unique light entities', () {
    expect(DeviceSlot.validate(DeviceSlot.demo), null);
    expect(DeviceSlot.validate(DeviceSlot.defaults), isNotNull);
    expect(
      DeviceSlot.validate(
        DeviceSlot.demo.map((s) => s.copyWith(entityId: 'light.same')).toList(),
      ),
      isNotNull,
    );
  });
  test(
    'RGB clamps, temperature clamps and unsupported scene fields skip',
    () async {
      final backend = DemoLights(latency: Duration.zero);
      addTearDown(backend.dispose);
      final light = (await backend.getLights()).first;
      expect(
        const LightCommand(rgb: RgbColor(300, -5, 128))
            .toServiceData(light)['rgb_color'],
        [255, 0, 128],
      );
      expect(
        const LightCommand(kelvin: 100)
            .toServiceData(light)['color_temp_kelvin'],
        2000,
      );
      final basic = LightEntity.fromJson({
        'entity_id': 'light.basic',
        'state': 'off',
      });
      expect(
        const LightCommand(
          brightnessPercent: 30,
          kelvin: 3000,
        ).toServiceData(basic),
        {'entity_id': 'light.basic'},
      );
      expect(const LightCommand(brightnessPercent: 0).service, 'turn_off');
    },
  );
  test('Movie scene drives mock room to specified states', () async {
    final backend = DemoLights(latency: Duration.zero);
    addTearDown(backend.dispose);
    final movie = LightScene.defaults.singleWhere((s) => s.id == 'movie');
    for (final slot in DeviceSlot.demo) {
      await backend.command(
        await backend.getLight(slot.entityId!),
        movie.commands[slot.id]!,
      );
    }
    expect((await backend.getLight('light.wipro_tube_1')).isOn, false);
    expect((await backend.getLight('light.wipro_tube_2')).isOn, false);
    final strip = await backend.getLight('light.tapo_strip');
    expect(strip.brightnessPercent, 15);
    expect(strip.rgbColor!.toJson(), [90, 30, 255]);
  });
}
