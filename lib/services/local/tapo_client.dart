import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/connection_config.dart';
import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../device_exception.dart';
import 'color_math.dart';
import 'crypto_utils.dart';
import 'device_client.dart';
import 'tapo_aes.dart';

/// Tapo KLAP v1/v2. Wire-format references and licenses: THIRD_PARTY_NOTICES.md.
class KlapCipher {
  KlapCipher(List<int> local, List<int> remote, List<int> auth) {
    final seed = [...local, ...remote, ...auth];
    key = sha256([...ascii.encode('lsk'), ...seed]).sublist(0, 16);
    final ivHash = sha256([...ascii.encode('iv'), ...seed]);
    iv = ivHash.sublist(0, 12);
    sequence = readU32(ivHash, 28).toSigned(32);
    signature = sha256([...ascii.encode('ldk'), ...seed]).sublist(0, 28);
  }
  late final Uint8List key, iv, signature;
  late int sequence;
  Uint8List encrypt(List<int> data) {
    sequence = (sequence + 1).toSigned(32);
    final cipher = aesBlock(data, key, iv: [...iv, ...u32(sequence)]);
    return bytes([
      ...sha256([...signature, ...u32(sequence), ...cipher]),
      ...cipher,
    ]);
  }

  Uint8List decrypt(List<int> data) {
    if (data.length < 48 ||
        !equalBytes(
          data.sublist(0, 32),
          sha256([...signature, ...u32(sequence), ...data.sublist(32)]),
        )) {
      throw const FormatException('Tapo response authentication failed.');
    }
    return aesBlock(
      data.sublist(32),
      key,
      iv: [...iv, ...u32(sequence)],
      encrypt: false,
    );
  }
}

class TapoClient implements DeviceClient {
  TapoClient(
    this.config, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _clientFactory = clientFactory ?? (() => http.Client());
  final DeviceConnection config;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  late http.Client _http = _clientFactory();
  final _queue = DeviceQueue();
  KlapCipher? _cipher;
  TapoAesCipher? _aes;
  String? _token;
  String? _cookie;
  DateTime? _expires, _authRetryAt;
  bool _disposed = false;

  Future<http.Response> _post(
    String path,
    List<int> body, {
    Map<String, String>? query,
    String contentType = 'application/octet-stream',
  }) async {
    if (_disposed) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Connection closed.',
      );
    }
    final request =
        http.Request(
            'POST',
            Uri(
              scheme: 'http',
              host: config.host,
              path: path,
              queryParameters: query,
            ),
          )
          ..followRedirects = false
          ..headers['Content-Type'] = contentType
          ..bodyBytes = body;
    if (_cookie != null) request.headers['Cookie'] = _cookie!;
    final response = await _http.send(request).timeout(timeout);
    final buffer = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(timeout)) {
      buffer.add(part);
      if (buffer.length > 65536) {
        throw const FormatException('Oversized device response.');
      }
    }
    return http.Response.bytes(
      buffer.takeBytes(),
      response.statusCode,
      headers: response.headers,
    );
  }

  /// Only numeric status/code metadata may reach the UI, never response bodies.
  String _responseSummary(http.Response response) {
    int? code;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error_code'] is int) {
        code = body['error_code'] as int;
      }
    } catch (_) {
      // KLAP success is binary; HTML and non-JSON failures are also possible.
    }
    return 'HTTP ${response.statusCode}'
        '${code == null ? ', ${response.bodyBytes.length} bytes' : ', code $code'}';
  }

  DeviceException _httpFailure(http.Response response, String stage) {
    final status = response.statusCode;
    return DeviceException(
      status == 401 || status == 403
          ? DeviceError.unauthorized
          : DeviceError.server,
      'Tapo $stage failed (${_responseSummary(response)}). '
      '${status == 429 ? 'The light is limiting requests. Wait a minute before retrying.' : 'Check the light’s IP and firmware. This response does not establish whether Third-Party Compatibility is enabled.'}',
    );
  }

  void _setSession(http.Response response) {
    final header = response.headers['set-cookie'] ?? '';
    final match = RegExp(r'TP_SESSIONID=([^;,\s]+)').firstMatch(header);
    if (match == null) {
      throw const DeviceException(
        DeviceError.malformed,
        'Tapo handshake returned no session cookie. Check the IP and firmware.',
      );
    }
    _cookie = 'TP_SESSIONID=${match.group(1)}';
    final seconds =
        int.tryParse(
          RegExp(r'TIMEOUT=(\d+)').firstMatch(header)?.group(1) ?? '',
        ) ??
        86400;
    _expires = DateTime.now().add(
      Duration(seconds: (seconds - 60).clamp(1, 86400)),
    );
  }

  Map<String, dynamic> _result(Object? data, String stage) {
    if (data is! Map || data['error_code'] is! int) {
      throw const FormatException('Invalid Tapo reply.');
    }
    final code = data['error_code'] as int;
    if (code != 0) {
      final badCredentials = code == -1501 || code == -20601;
      if (badCredentials) {
        _authRetryAt = DateTime.now().add(const Duration(minutes: 1));
      }
      throw DeviceException(
        badCredentials ? DeviceError.unauthorized : DeviceError.server,
        'Tapo $stage was rejected (code $code). '
        '${badCredentials
            ? 'Check the owning account email and password, then retry in a minute.'
            : code == 9999
            ? 'The session expired. Refresh to reconnect.'
            : 'Check the light’s firmware compatibility.'}',
      );
    }
    return data['result'] is Map
        ? Map<String, dynamic>.from(data['result'] as Map)
        : {};
  }

  Future<http.Response> _postJson(Map<String, dynamic> data, {String? token}) =>
      _post(
        '/app',
        utf8.encode(jsonEncode(data)),
        contentType: 'application/json',
        query: token == null ? null : {'token': token},
      );

  Future<Map<String, dynamic>> _aesRequest(
    Map<String, dynamic> data,
    String stage,
  ) async {
    final response = await _postJson({
      'method': 'securePassthrough',
      'params': {'request': _aes!.encrypt(data)},
    }, token: _token);
    if (response.statusCode != 200) throw _httpFailure(response, stage);
    final outer = _result(jsonDecode(response.body), stage);
    if (outer['response'] is! String) {
      throw const FormatException('Missing encrypted Tapo reply.');
    }
    return _result(_aes!.decrypt(outer['response'] as String), stage);
  }

  Future<void> _aesHandshake(http.Response klapResponse) async {
    final keys = await TapoAesHandshake.generate();
    final response = await _postJson({
      'method': 'handshake',
      'params': {'key': keys.publicKeyPem, 'requestTimeMils': 0},
    });
    Object? data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      // Report both attempts without printing arbitrary device content.
    }
    if (response.statusCode != 200 ||
        data is! Map ||
        data['error_code'] != 0 ||
        data['result'] is! Map ||
        (data['result'] as Map)['key'] is! String) {
      throw DeviceException(
        DeviceError.unavailable,
        'Tapo could not start a supported local session '
        '(KLAP: ${_responseSummary(klapResponse)}; AES: ${_responseSummary(response)}). '
        'If Third-Party Compatibility is already enabled, check the IP and firmware version. TPAP-only firmware is not supported.',
      );
    }
    // Credentials are sent only after a valid RSA/AES exchange and cookie.
    _aes = keys.finish((data['result'] as Map)['key'] as String);
    _setSession(response);
    final login = await _aesRequest({
      'method': 'login_device',
      'params': TapoAesCipher.loginParams(config.email, config.password),
      'requestTimeMils': DateTime.now().millisecondsSinceEpoch,
    }, 'AES login');
    final token = login['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Missing Tapo login token.');
    }
    _token = token;
  }

  Future<void> _handshake() async {
    if (_authRetryAt != null && DateTime.now().isBefore(_authRetryAt!)) {
      throw const DeviceException(
        DeviceError.unauthorized,
        'Tapo authentication is cooling down. Check the owning account email and password, then retry in a minute.',
      );
    }
    _cookie = null;
    _token = null;
    _cipher = null;
    _aes = null;
    final local = randomBytes(16);
    final response = await _post('/app/handshake1', local);
    if (response.statusCode != 200 || response.bodyBytes.length != 48) {
      // An absent/rejected KLAP endpoint may belong to a legacy AES light.
      // Never downgrade after a valid KLAP challenge fails authentication.
      if ({200, 403, 404, 405}.contains(response.statusCode)) {
        await _aesHandshake(response);
        return;
      }
      throw _httpFailure(response, 'KLAP handshake');
    }
    final remote = response.bodyBytes.sublist(0, 16);
    final proof = response.bodyBytes.sublist(16);
    final user = utf8.encode(config.email.trim()),
        pass = utf8.encode(config.password);
    final v2 = sha256([...sha1(user), ...sha1(pass)]);
    String hex(List<int> value) =>
        value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final v1 = md5(ascii.encode('${hex(md5(user))}${hex(md5(pass))}'));
    List<int>? auth;
    bool modern = true;
    if (equalBytes(proof, sha256([...local, ...remote, ...v2]))) {
      auth = v2;
    } else if (equalBytes(proof, sha256([...local, ...v1]))) {
      auth = v1;
      modern = false;
    }
    if (auth == null) {
      _authRetryAt = DateTime.now().add(const Duration(minutes: 1));
      throw const DeviceException(
        DeviceError.unauthorized,
        'Tapo email or password was rejected by this light. Check account capitalization and the light’s IP address.',
      );
    }
    _setSession(response);
    final finish = await _post(
      '/app/handshake2',
      sha256([...remote, if (modern) ...local, ...auth]),
    );
    if (finish.statusCode != 200) {
      throw _httpFailure(finish, 'KLAP handshake step 2');
    }
    _cipher = KlapCipher(local, remote, auth);
  }

  Future<Map<String, dynamic>> _request(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    try {
      if ((_cipher == null && _aes == null) ||
          _expires == null ||
          DateTime.now().isAfter(_expires!)) {
        await _handshake();
      }
      final request = {
        'method': method,
        'requestTimeMils': DateTime.now().millisecondsSinceEpoch,
        'params': ?params,
      };
      if (_aes != null) return await _aesRequest(request, 'AES request');
      final cipher = _cipher!;
      final body = cipher.encrypt(utf8.encode(jsonEncode(request)));
      final response = await _post(
        '/app/request',
        body,
        query: {'seq': '${cipher.sequence}'},
      );
      if (response.statusCode != 200) {
        throw _httpFailure(response, 'KLAP request');
      }
      final data = jsonDecode(utf8.decode(cipher.decrypt(response.bodyBytes)));
      return _result(data, 'KLAP request');
    } catch (error) {
      _cipher = null;
      _aes = null;
      _token = null;
      _cookie = null;
      _expires = null;
      _http.close();
      if (!_disposed) _http = _clientFactory();
      if (error is DeviceException) rethrow;
      if (error is TimeoutException) {
        throw const DeviceException(
          DeviceError.timeout,
          'Tapo timed out. Check the light’s power, IP address and Wi-Fi.',
        );
      }
      if (error is FormatException) {
        throw const DeviceException(
          DeviceError.malformed,
          'Tapo returned an invalid or unauthenticated response. Check the firmware and credentials.',
        );
      }
      throw const DeviceException(
        DeviceError.unreachable,
        'Cannot reach Tapo. Join the same Wi-Fi and check its IP address.',
      );
    }
  }

  @override
  Future<LightEntity> read() => _queue.run(() async {
    final info = await _request('get_device_info');
    if (info['device_on'] is! bool) {
      throw const DeviceException(
        DeviceError.malformed,
        'This Tapo device did not report a light power state.',
      );
    }
    final hue = safeInt(info['hue']), saturation = safeInt(info['saturation']);
    final temp = safeInt(info['color_temp']);
    final range = info['color_temp_range'];
    final minTemp = range is List && range.length == 2
        ? safeInt(range.first)
        : null;
    final maxTemp = range is List && range.length == 2
        ? safeInt(range.last)
        : null;
    final adjustableWhite =
        minTemp != null && maxTemp != null && minTemp > 0 && maxTemp > minTemp;
    final modes = <String>[
      if (hue != null && saturation != null) 'rgb',
      if (temp != null && adjustableWhite) 'color_temp',
    ];
    if (modes.isEmpty) {
      modes.add(info['brightness'] is num ? 'brightness' : 'onoff');
    }
    final effect = info['lighting_effect'];
    final level = effect is Map && effect['enable'] == 1
        ? safeInt(effect['brightness'])
        : safeInt(info['brightness']);
    return LightEntity(
      entityId: config.entityId,
      friendlyName: config.name,
      state: info['device_on'] == true ? 'on' : 'off',
      attributes: {
        'brightness': percentToBrightness(level ?? 100),
        if (hue != null && saturation != null)
          'rgb_color': hsvToRgb(hue, saturation / 100).toJson(),
        if (temp != null && temp > 0) 'color_temp_kelvin': temp,
        'min_color_temp_kelvin': range is List && range.length == 2
            ? safeInt(range.first) ?? 2500
            : 2500,
        'max_color_temp_kelvin': range is List && range.length == 2
            ? safeInt(range.last) ?? 6500
            : 6500,
        'supported_color_modes': modes,
        'color_mode': temp != null && temp > 0 ? 'color_temp' : 'rgb',
        'has_lighting_effect': info['lighting_effect'] is Map,
        'model': info['model'] is String ? info['model'] : 'Tapo',
      },
    );
  });

  static Map<String, dynamic> commandData(
    LightEntity light,
    LightCommand command,
  ) {
    final data = <String, dynamic>{'device_on': command.service != 'turn_off'};
    if (command.service == 'turn_off') return data;
    if (command.brightnessPercent != null && light.supportsBrightness) {
      data['brightness'] = command.brightnessPercent!.round().clamp(1, 100);
    }
    if (command.rgb != null && light.supportsRgb) {
      final hsv = rgbToHsv(command.rgb!);
      data.addAll({
        'hue': hsv.hue.round() % 360,
        'saturation': (hsv.saturation * 100).round(),
        'color_temp': 0,
      });
    } else if (command.kelvin != null && light.supportsTemperature) {
      data.addAll({
        'color_temp': command.kelvin!.clamp(
          light.minColorTempKelvin,
          light.maxColorTempKelvin,
        ),
        'hue': 0,
        'saturation': 0,
      });
    }
    if (data.length > 1 && light.rawAttributes['has_lighting_effect'] == true) {
      data['lighting_effect'] = {'enable': 0};
    }
    return data;
  }

  @override
  Future<void> command(LightEntity light, LightCommand command) =>
      _queue.run(() async {
        await _request('set_device_info', commandData(light, command));
      });
  @override
  void dispose() {
    _disposed = true;
    _cipher = null;
    _aes = null;
    _token = null;
    _cookie = null;
    _http.close();
  }
}
