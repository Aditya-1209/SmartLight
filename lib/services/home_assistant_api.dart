import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/connection_config.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import 'ha_exception.dart';

class HomeAssistantApi {
  HomeAssistantApi(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();
  final ConnectionConfig config;
  final http.Client _client;
  final Duration timeout;

  Future<Object?> _request(String path, {Map<String, dynamic>? body}) async {
    try {
      final request =
          http.Request(body == null ? 'GET' : 'POST', config.endpoint(path))
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer ${config.token}',
              'Content-Type': 'application/json',
            });
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const HaException(
          HaError.unauthorized,
          'Unauthorized. Check your Home Assistant token.',
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const HaException(
          HaError.invalidUrl,
          'Home Assistant redirected the request. Enter its final URL.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HaException(
          HaError.server,
          'Home Assistant returned HTTP ${response.statusCode}.',
        );
      }
      return jsonDecode(response.body);
    } on TimeoutException {
      throw const HaException(
        HaError.timeout,
        'Home Assistant request timed out. Check your network.',
      );
    } on FormatException {
      throw const HaException(
        HaError.malformed,
        'Home Assistant returned invalid data.',
      );
    } on SocketException {
      throw const HaException(
        HaError.unreachable,
        'Home Assistant offline. Check your URL and Wi-Fi.',
      );
    } on http.ClientException {
      throw const HaException(
        HaError.unreachable,
        'Home Assistant unreachable. Check your network and HTTPS certificate.',
      );
    }
  }

  Future<void> testConnection() async {
    final result = await _request('/api/');
    if (result is! Map || result['message'] != 'API running.') {
      throw const HaException(
        HaError.malformed,
        'This URL did not return a Home Assistant API response.',
      );
    }
  }

  Future<List<LightEntity>> getLights() async {
    final result = await _request('/api/states');
    if (result is! List) {
      throw const HaException(
        HaError.malformed,
        'Home Assistant returned an invalid state list.',
      );
    }
    return result
        .whereType<Map<String, dynamic>>()
        .map(LightEntity.fromJson)
        .where((e) => e.entityId.startsWith('light.'))
        .toList();
  }

  Future<LightEntity> getLight(String id) async {
    final result = await _request('/api/states/${Uri.encodeComponent(id)}');
    if (result is! Map<String, dynamic> || result['entity_id'] != id) {
      throw const HaException(
        HaError.malformed,
        'Home Assistant returned an invalid light state.',
      );
    }
    return LightEntity.fromJson(result);
  }

  Future<void> command(LightEntity light, LightCommand command) async {
    await _request(
      '/api/services/light/${command.service}',
      body: command.toServiceData(light),
    );
  }

  void dispose() => _client.close();
}
