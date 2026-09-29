import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Used only by the explicit desktop setup flow, never by room controls.
class TuyaSetupException implements Exception {
  const TuyaSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TuyaCloudConfig {
  const TuyaCloudConfig({
    required this.clientId,
    required this.secret,
    required this.schema,
  });
  final String clientId, secret, schema;
  // This first desktop pairing flow uses the user's Central Europe project.
  static const host = 'openapi.tuyaeu.com';
  bool get valid =>
      RegExp(r'^[a-zA-Z0-9]{10,64}$').hasMatch(clientId) &&
      secret.length >= 16 &&
      secret.length <= 128 &&
      RegExp(r'^[a-zA-Z0-9_\-]{1,64}$').hasMatch(schema);
  Map<String, String> toJson() => {
    'clientId': clientId,
    'secret': secret,
    'schema': schema,
  };
  factory TuyaCloudConfig.fromJson(Map<String, dynamic> data) =>
      TuyaCloudConfig(
        clientId: data['clientId'] as String,
        secret: data['secret'] as String,
        schema: data['schema'] as String,
      );
  @override
  String toString() => 'TuyaCloudConfig(credentials redacted)';
}

class TuyaCloudSetup {
  TuyaCloudSetup(this.config, {http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final TuyaCloudConfig config;
  final http.Client _client;
  final DateTime Function() _now;
  String _token = '';
  DateTime? _expires;
  bool _closed = false;

  /// Tuya's current cloud HMAC signature. Path includes the sorted query.
  static String signature({
    required String clientId,
    required String secret,
    required String timestamp,
    required String method,
    required String path,
    String token = '',
    String body = '',
  }) {
    final digest = sha256.convert(utf8.encode(body));
    final toSign = '$clientId$token$timestamp$method\n$digest\n\n$path';
    return Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(toSign)).toString().toUpperCase();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _checkOpen();
    if (_expires == null || !_now().isBefore(_expires!)) {
      final token = await _send('GET', '/v1.0/token?grant_type=1', '', '');
      if (token is! Map ||
          token['access_token'] is! String ||
          token['expire_time'] is! num) {
        throw const TuyaSetupException(
          'Tuya returned an invalid setup session.',
        );
      }
      _token = token['access_token'] as String;
      _expires = _now().add(
        Duration(seconds: (token['expire_time'] as num).toInt() - 60),
      );
    }
    return _send(method, path, body == null ? '' : jsonEncode(body), _token);
  }

  Future<dynamic> _send(
    String method,
    String path,
    String body,
    String token,
  ) async {
    _checkOpen();
    final timestamp = '${_now().millisecondsSinceEpoch}';
    final request =
        http.Request(method, Uri.parse('https://${TuyaCloudConfig.host}$path'))
          ..followRedirects = false
          ..headers.addAll({
            'client_id': config.clientId,
            't': timestamp,
            'sign_method': 'HMAC-SHA256',
            'sign': signature(
              clientId: config.clientId,
              secret: config.secret,
              timestamp: timestamp,
              method: method,
              path: path,
              body: body,
              token: token,
            ),
            if (token.isNotEmpty) 'access_token': token,
            'Content-Type': 'application/json',
          })
          ..body = body;
    try {
      final response = await (() async {
        final streamed = await _client.send(request);
        if (streamed.statusCode != 200) {
          throw TuyaSetupException(
            'Tuya setup returned HTTP ${streamed.statusCode}.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const TuyaSetupException(
              'Tuya setup response was too large.',
            );
          }
        }
        return jsonDecode(utf8.decode(bytes));
      })().timeout(const Duration(seconds: 20));
      _checkOpen();
      if (response is! Map) throw const FormatException();
      if (response['success'] != true) {
        // Do not echo vendor messages: they can contain credentials or identifiers.
        final code = '${response['code']}';
        final safeCode = RegExp(r'^\d{1,8}$').hasMatch(code) ? code : 'unknown';
        final detail = switch (safeCode) {
          '1106' => 'Link the SmartLight SDK app under Devices → Link My App in this project.',
          '1004' => 'Check the cloud project Access ID and Access Secret.',
          '1010' => 'The setup session expired. Try again.',
          '28841002' => 'The project’s IoT Core trial is unavailable. Check its trial status; do not buy a plan.',
          _ => 'Check the project’s app link and active API services.',
        };
        throw TuyaSetupException('Tuya setup error $safeCode. $detail');
      }
      return response['result'];
    } on TuyaSetupException {
      rethrow;
    } on TimeoutException {
      throw const TuyaSetupException(
        'Tuya setup timed out. Check your internet connection.',
      );
    } catch (_) {
      _checkOpen();
      throw const TuyaSetupException(
        'Could not reach Tuya for setup. Check your internet connection.',
      );
    }
  }

  void _checkOpen() {
    if (_closed) throw const TuyaSetupException('Setup cancelled.');
  }

  void close() {
    _closed = true;
    _token = '';
    _client.close();
  }
}
