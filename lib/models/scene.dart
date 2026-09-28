import 'light_command.dart';
import 'light_entity.dart';

class LightScene {
  const LightScene(this.id, this.name, this.description, this.commands);
  final String id;
  final String name;
  final String description;
  final Map<String, LightCommand> commands;
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
