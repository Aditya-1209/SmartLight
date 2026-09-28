import 'dart:math' as math;

import '../../models/light_entity.dart';

({double hue, double saturation, double value}) rgbToHsv(RgbColor rgb) {
  final c = rgb.toJson().map((v) => v / 255).toList();
  final max = c.reduce(math.max), min = c.reduce(math.min), delta = max - min;
  double hue = 0;
  if (delta != 0) {
    hue = max == c[0]
        ? 60 * ((c[1] - c[2]) / delta % 6)
        : max == c[1]
        ? 60 * ((c[2] - c[0]) / delta + 2)
        : 60 * ((c[0] - c[1]) / delta + 4);
  }
  return (hue: hue % 360, saturation: max == 0 ? 0 : delta / max, value: max);
}

RgbColor hsvToRgb(num hue, num saturation, [num value = 1]) {
  final h = (hue % 360) / 60, s = saturation.clamp(0, 1), v = value.clamp(0, 1);
  final c = v * s, x = c * (1 - (h % 2 - 1).abs()), m = v - c;
  final parts = switch (h.floor()) {
    0 => [c, x, 0],
    1 => [x, c, 0],
    2 => [0, c, x],
    3 => [0, x, c],
    4 => [x, 0, c],
    _ => [c, 0, x],
  };
  return RgbColor(
    ((parts[0] + m) * 255).round(),
    ((parts[1] + m) * 255).round(),
    ((parts[2] + m) * 255).round(),
  );
}
