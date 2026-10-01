import 'light_command.dart';
import 'light_entity.dart';

class LightScene {
  const LightScene(
    this.id,
    this.name,
    this.description,
    this.commands, {
    this.appearance = 'sparkle',
  });
  final String id;
  final String name;
  final String description;
  final Map<String, LightCommand> commands;
  final String appearance;
  bool get isCustom => id.startsWith('custom-');
  String get style => isCustom ? appearance : id;
  static const appearances = [
    'sparkle',
    'study',
    'movie',
    'chill',
    'sleep',
    'music',
  ];
  static const maxCustomScenes = 60;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'appearance': appearance,
    'commands': {
      for (final entry in commands.entries)
        entry.key: {
          'on': entry.value.on,
          if (entry.value.brightnessPercent != null)
            'brightness': entry.value.brightnessPercent,
          if (entry.value.rgb != null) 'rgb': entry.value.rgb!.toJson(),
          if (entry.value.kelvin != null) 'kelvin': entry.value.kelvin,
        },
    },
  };

  factory LightScene.fromJson(Map<String, dynamic> json) {
    final id = json['id'],
        name = json['name'],
        description = json['description'] ?? '';
    final appearance = json['appearance'] ?? 'sparkle', raw = json['commands'];
    if (id is! String ||
        !RegExp(r'^custom-[a-zA-Z0-9-]{1,80}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 60 ||
        description is! String ||
        description.length > 160 ||
        !appearances.contains(appearance) ||
        raw is! Map ||
        raw.isEmpty ||
        raw.length > 3) {
      throw const FormatException('Invalid scene.');
    }
    final commands = <String, LightCommand>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (!const ['tube1', 'tube2', 'strip'].contains(entry.key) ||
          value is! Map ||
          value['on'] is! bool) {
        throw const FormatException('Invalid scene light.');
      }
      final brightness = value['brightness'],
          rgb = value['rgb'],
          kelvin = value['kelvin'];
      if (brightness != null &&
              (brightness is! num ||
                  !brightness.isFinite ||
                  brightness < 0 ||
                  brightness > 100) ||
          kelvin != null &&
              (kelvin is! int || kelvin < 1000 || kelvin > 20000) ||
          rgb != null &&
              (rgb is! List ||
                  rgb.length != 3 ||
                  rgb.any((v) => v is! int || v < 0 || v > 255)) ||
          rgb != null && kelvin != null) {
        throw const FormatException('Invalid scene controls.');
      }
      commands[entry.key as String] = LightCommand(
        on: value['on'] as bool,
        brightnessPercent: (brightness as num?)?.toDouble(),
        rgb: RgbColor.parse(rgb),
        kelvin: kelvin as int?,
      );
    }
    return LightScene(
      id,
      name.trim(),
      description.trim(),
      Map.unmodifiable(commands),
      appearance: appearance as String,
    );
  }

  /// Capture only available lights, using their active color mode.
  static LightCommand capture(LightEntity light) => !light.isOn
      ? const LightCommand(on: false)
      : LightCommand(
          brightnessPercent: light.supportsBrightness
              ? light.brightnessPercent.toDouble()
              : null,
          rgb:
              light.supportsRgb &&
                  light.rawAttributes['color_mode'] != 'color_temp'
              ? light.rgbColor
              : null,
          kelvin:
              light.supportsTemperature &&
                  (light.rawAttributes['color_mode'] == 'color_temp' ||
                      light.rgbColor == null)
              ? light.colorTempKelvin
              : null,
        );
  static const defaults = [
    LightScene('study', 'Study', 'A clear mind. A brighter room.', {
      'tube1': LightCommand(brightnessPercent: 100, kelvin: 4500),
      'tube2': LightCommand(brightnessPercent: 100, kelvin: 4500),
      'strip': LightCommand(brightnessPercent: 60, kelvin: 4500),
    }),
    LightScene('movie', 'Movie', 'Lights down. Settle in.', {
      'tube1': LightCommand(on: false),
      'tube2': LightCommand(on: false),
      'strip': LightCommand(brightnessPercent: 15, rgb: RgbColor(90, 30, 255)),
    }),
    LightScene('chill', 'Chill', 'A little warmth. A slower pace.', {
      'tube1': LightCommand(brightnessPercent: 30, kelvin: 2700),
      'tube2': LightCommand(brightnessPercent: 30, kelvin: 2700),
      'strip': LightCommand(brightnessPercent: 25, rgb: RgbColor(190, 90, 220)),
    }),
    LightScene('sleep', 'Sleep', 'A soft glow to end the day.', {
      'tube1': LightCommand(on: false),
      'tube2': LightCommand(on: false),
      'strip': LightCommand(brightnessPercent: 5, rgb: RgbColor(255, 45, 15)),
    }),
  ];
}
