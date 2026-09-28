int? safeInt(Object? value) =>
    value is num && value.isFinite ? value.round() : null;

int brightnessToPercent(int value) => (value.clamp(0, 255) * 100 / 255).round();
int percentToBrightness(num value) =>
    value.isFinite ? (value.clamp(0, 100) * 255 / 100).round() : 0;

class RgbColor {
  const RgbColor(this.red, this.green, this.blue);
  final int red;
  final int green;
  final int blue;
  List<int> toJson() => [red, green, blue].map((v) => v.clamp(0, 255)).toList();
  static RgbColor? parse(Object? raw) {
    if (raw is! List || raw.length != 3) return null;
    final values = raw.map(safeInt).toList();
    if (values.contains(null)) return null;
    return RgbColor(values[0]!, values[1]!, values[2]!);
  }
}

class LightEntity {
  LightEntity({
    required this.entityId,
    required this.friendlyName,
    required this.state,
    required Map<String, dynamic> attributes,
  }) : rawAttributes = Map.unmodifiable(attributes);

  factory LightEntity.fromJson(Map<String, dynamic> json) {
    final raw = json['attributes'];
    final attrs = raw is Map
        ? Map<String, dynamic>.fromEntries(
            raw.entries
                .where((e) => e.key is String)
                .map((e) => MapEntry(e.key as String, e.value)),
          )
        : <String, dynamic>{};
    final id = json['entity_id'] is String ? json['entity_id'] as String : '';
    return LightEntity(
      entityId: id,
      friendlyName: attrs['friendly_name'] is String
          ? attrs['friendly_name'] as String
          : id,
      state: json['state'] is String ? json['state'] as String : 'unknown',
      attributes: attrs,
    );
  }

  final String entityId;
  final String friendlyName;
  final String state;
  final Map<String, dynamic> rawAttributes;
  bool get isOn => state == 'on';
  bool get available => state == 'on' || state == 'off';
  int? get brightness => safeInt(rawAttributes['brightness'])?.clamp(0, 255);
  int get brightnessPercent =>
      isOn ? brightnessToPercent(brightness ?? 255) : 0;
  RgbColor? get rgbColor => RgbColor.parse(rawAttributes['rgb_color']);
  int? _kelvin(String key, String legacy) {
    final modern = safeInt(rawAttributes[key]);
    if (modern != null && modern > 0) return modern;
    final mireds = safeInt(rawAttributes[legacy]);
    return mireds != null && mireds > 0 ? (1000000 / mireds).round() : null;
  }

  int? get colorTempKelvin => _kelvin('color_temp_kelvin', 'color_temp');
  int get minColorTempKelvin =>
      _kelvin('min_color_temp_kelvin', 'max_mireds')?.clamp(1000, 20000) ??
      2000;
  int get maxColorTempKelvin =>
      (_kelvin('max_color_temp_kelvin', 'min_mireds') ?? 6500).clamp(
        minColorTempKelvin,
        20000,
      );
  Set<String> get supportedColorModes {
    final raw = rawAttributes['supported_color_modes'];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  int get _legacyFeatures => safeInt(rawAttributes['supported_features']) ?? 0;
  bool get supportsBrightness =>
      supportedColorModes.any(
        (m) => const {
          'brightness',
          'color_temp',
          'hs',
          'xy',
          'rgb',
          'rgbw',
          'rgbww',
          'white',
        }.contains(m),
      ) ||
      (supportedColorModes.isEmpty && (_legacyFeatures & 1) != 0);
  bool get supportsRgb =>
      supportedColorModes.any(
        (m) => const {'rgb', 'rgbw', 'rgbww', 'hs', 'xy'}.contains(m),
      ) ||
      (supportedColorModes.isEmpty && (_legacyFeatures & 16) != 0);
  bool get supportsTemperature =>
      supportedColorModes.contains('color_temp') ||
      (supportedColorModes.isEmpty && (_legacyFeatures & 2) != 0);
  Map<String, dynamic> toJson() => {
    'entity_id': entityId,
    'state': state,
    'attributes': rawAttributes,
  };
}
