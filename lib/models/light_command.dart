import 'light_entity.dart';

class LightCommand {
  const LightCommand({
    this.on = true,
    this.brightnessPercent,
    this.rgb,
    this.kelvin,
  });
  final bool on;
  final double? brightnessPercent;
  final RgbColor? rgb;
  final int? kelvin;
  String get service => !on || brightnessPercent == 0 ? 'turn_off' : 'turn_on';
  bool compatibleWith(LightEntity light) =>
      brightnessPercent == null && rgb == null && kelvin == null ||
      brightnessPercent != null && light.supportsBrightness ||
      rgb != null && light.supportsRgb ||
      kelvin != null && light.supportsTemperature;

  Map<String, dynamic> toServiceData(LightEntity light) {
    final data = <String, dynamic>{'entity_id': light.entityId};
    if (service == 'turn_off') return data;
    if (brightnessPercent != null && light.supportsBrightness) {
      data['brightness'] = percentToBrightness(brightnessPercent!);
    }
    if (rgb != null && light.supportsRgb) {
      data['rgb_color'] = rgb!.toJson();
    } else if (kelvin != null && light.supportsTemperature) {
      data['color_temp_kelvin'] = kelvin!.clamp(
        light.minColorTempKelvin,
        light.maxColorTempKelvin,
      );
    }
    // Preserve a visible brightness when changing an off light’s color.
    if ((data.containsKey('rgb_color') ||
            data.containsKey('color_temp_kelvin')) &&
        !data.containsKey('brightness') &&
        light.supportsBrightness) {
      data['brightness'] = (light.brightness ?? 180).clamp(13, 255);
    }
    return data;
  }
}
