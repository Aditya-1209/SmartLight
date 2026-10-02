import '../../models/connection_config.dart';
import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../models/light_timer.dart';
import '../device_exception.dart';
import 'color_math.dart';
import 'device_client.dart';
import 'device_timer_client.dart';
import 'tuya_protocol.dart';

class TuyaLightMapper {
  TuyaLightMapper(this.config);
  final DeviceConnection config;
  bool get modern => config.profile == TuyaProfile.modern;
  String get power => modern ? '20' : '1';
  String get mode => modern ? '21' : '2';
  String get brightness => modern ? '22' : '3';
  String get temperature => modern ? '23' : '4';
  String get color => modern ? '24' : '5';
  int get scale => modern ? 1000 : 255;
  int get minBrightness => modern ? 10 : 25;
  String _hex(int value, int width) =>
      value.toRadixString(16).padLeft(width, '0');
  ({double hue, double saturation, double value})? _decodeColor(Object? raw) {
    if (raw is! String ||
        !RegExp(modern ? r'^[0-9a-fA-F]{12}$' : r'^[0-9a-fA-F]{14}$')
            .hasMatch(raw)) {
      return null;
    }
    int number(int start, int end) =>
        int.parse(raw.substring(start, end), radix: 16);
    return modern
        ? (
            hue: number(0, 4).toDouble(),
            saturation: number(4, 8) / 1000,
            value: number(8, 12) / 1000,
          )
        : (
            hue: number(6, 10).toDouble(),
            saturation: number(10, 12) / 255,
            value: number(12, 14) / 255,
          );
  }

  String _encodeColor(double hue, double saturation, double value) {
    final h = hue.round() % 360,
        s = (saturation.clamp(0, 1) * scale).round(),
        v = (value.clamp(0.01, 1) * scale).round();
    if (modern) return '${_hex(h, 4)}${_hex(s, 4)}${_hex(v, 4)}';
    final rgb = hsvToRgb(
      hue,
      saturation,
      value,
    ).toJson().map((c) => _hex(c, 2)).join();
    return '$rgb${_hex(h, 4)}${_hex(s, 2)}${_hex(v, 2)}';
  }

  LightEntity parse(Map<String, dynamic> dps) {
    if (dps[power] is! bool) {
      throw const DeviceException(
        DeviceError.malformed,
        'This light does not match the selected profile. Try the other Wipro/Tuya profile in setup.',
      );
    }
    final hsv = _decodeColor(dps[color]);
    final inColor = dps[mode] == 'colour';
    final bright = inColor && hsv != null
        ? hsv.value * 100
        : (safeInt(dps[brightness]) ?? scale) * 100 / scale;
    final temp = safeInt(dps[temperature]);
    final supportsMode = dps[mode] is String;
    final modes = <String>[
      if (supportsMode && hsv != null) 'rgb',
      if (supportsMode && temp != null) 'color_temp',
    ];
    if (modes.isEmpty) {
      modes.add(dps[brightness] is num ? 'brightness' : 'onoff');
    }
    return LightEntity(
      entityId: config.entityId,
      friendlyName: config.name,
      state: dps[power] == true ? 'on' : 'off',
      attributes: {
        'brightness': percentToBrightness(bright),
        if (hsv != null)
          'rgb_color': hsvToRgb(hsv.hue, hsv.saturation).toJson(),
        if (temp != null)
          'color_temp_kelvin':
              (config.minKelvin +
                      temp.clamp(0, scale) /
                          scale *
                          (config.maxKelvin - config.minKelvin))
                  .round(),
        'min_color_temp_kelvin': config.minKelvin,
        'max_color_temp_kelvin': config.maxKelvin,
        'supported_color_modes': modes,
        'color_mode': inColor ? 'rgb' : 'color_temp',
        // Contains state only; credentials never enter diagnostics or preferences.
        'dps': Map<String, dynamic>.unmodifiable(dps),
      },
    );
  }

  Map<String, dynamic> commandData(LightEntity light, LightCommand command) {
    final data = <String, dynamic>{power: command.service != 'turn_off'};
    if (command.service == 'turn_off') return data;
    final level =
        (command.brightnessPercent ??
                brightnessToPercent(light.brightness ?? 180))
            .clamp(1, 100) /
        100;
    final current = light.rawAttributes['dps'] is Map
        ? light.rawAttributes['dps'] as Map
        : const {};
    final inColor = current[mode] == 'colour';
    if (command.rgb != null && light.supportsRgb) {
      final hsv = rgbToHsv(command.rgb!);
      data.addAll({
        mode: 'colour',
        color: _encodeColor(hsv.hue, hsv.saturation, level),
      });
    } else if (command.kelvin != null && light.supportsTemperature) {
      data.addAll({
        mode: 'white',
        temperature:
            ((command.kelvin!.clamp(config.minKelvin, config.maxKelvin) -
                        config.minKelvin) *
                    scale /
                    (config.maxKelvin - config.minKelvin))
                .round(),
      });
      if (light.supportsBrightness) {
        data[brightness] = (level * scale).round().clamp(minBrightness, scale);
      }
    } else if (command.brightnessPercent != null && light.supportsBrightness) {
      final hsv = _decodeColor(current[color]);
      if (inColor && hsv != null && light.supportsRgb) {
        data[color] = _encodeColor(hsv.hue, hsv.saturation, level);
      } else {
        data[brightness] = (level * scale).round().clamp(minBrightness, scale);
      }
    }
    return data;
  }
}

class TuyaClient implements DeviceClient, DeviceTimerClient {
  TuyaClient(DeviceConnection config, {TuyaTransport? transport})
    : _transport = transport ?? TuyaTransport(config),
      _mapper = TuyaLightMapper(config);
  final TuyaTransport _transport;
  final TuyaLightMapper _mapper;
  final _queue = DeviceQueue();

  LightTimerStatus _timerStatus(Map<String, dynamic> dps) {
    final light = _mapper.parse(dps);
    final seconds = dps['26'];
    if (!_mapper.modern || seconds is! int || seconds < 0 || seconds > 86400) {
      return LightTimerStatus(
        isOn: light.isOn,
        unsupportedReason:
            'This light does not report a supported built-in timer.',
      );
    }
    return LightTimerStatus(
      isOn: light.isOn,
      togglesPower: true,
      active: seconds == 0
          ? null
          : LightTimer(
              id: 'countdown',
              endsAt: DateTime.now().add(Duration(seconds: seconds)),
              on: !light.isOn,
            ),
    );
  }

  Future<LightTimerStatus> _readTimer() async =>
      _timerStatus(await _transport.exchange());

  @override
  Future<LightTimerStatus> readTimer() => _queue.run(_readTimer);

  @override
  Future<LightTimerStatus> setTimer(DateTime endsAt, {required bool on}) =>
      _queue.run(() async {
        final current = await _readTimer();
        requireTimerAvailable(current, on);
        final seconds = countdownSeconds(endsAt);
        try {
          // DP26 reverses power; never change power to make a timer fit.
          await _transport.exchange(dps: {'26': seconds});
          final confirmed = await _readTimer();
          final timer = confirmed.active;
          if (timer == null ||
              timer.on != on ||
              timer.endsAt.difference(endsAt).inSeconds.abs() > 35) {
            throw timerUnconfirmed;
          }
          return confirmed;
        } catch (_) {
          // Do not replay a write whose acknowledgement/read-back was lost.
          throw timerUnconfirmed;
        }
      });

  @override
  Future<LightTimerStatus> cancelTimer() => _queue.run(() async {
    final current = await _readTimer();
    if (!current.supported) {
      throw DeviceException(
        DeviceError.unavailable,
        current.unsupportedReason!,
      );
    }
    if (current.active == null) return current;
    try {
      await _transport.exchange(dps: {'26': 0});
      final confirmed = await _readTimer();
      if (confirmed.active != null || !confirmed.supported) {
        throw timerUnconfirmed;
      }
      return confirmed;
    } catch (_) {
      throw timerUnconfirmed;
    }
  });
  @override
  Future<LightEntity> read() =>
      _queue.run(() async => _mapper.parse(await _transport.exchange()));
  @override
  Future<void> command(LightEntity light, LightCommand command) =>
      _queue.run(() async {
        await _transport.exchange(dps: _mapper.commandData(light, command));
      });
  @override
  void dispose() => _transport.dispose();
}
