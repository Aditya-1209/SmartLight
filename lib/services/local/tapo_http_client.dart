import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/connection_config.dart';

/// HTTP/1.1 transport with explicit framing for embedded Tapo HTTP servers.
/// Keeps dart:io's platform network policy and connection pooling in place.
class TapoHttpClient extends http.BaseClient {
  TapoHttpClient({
    HttpClient? client,
    Duration timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient() {
    _client
      ..connectionTimeout = timeout
      ..autoUncompress = false
      ..findProxy = (_) => 'DIRECT';
  }

  final HttpClient _client;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Connection closed.');
    final url = request.url;
    if (url.scheme != 'http' ||
        url.port != 80 ||
        !DeviceConnection.isLocalAddress(url.host) ||
        url.userInfo.isNotEmpty) {
      throw http.ClientException('Tapo requires a local IPv4 HTTP address.');
    }
    final length = request.contentLength;
    if (length == null || length < 0) {
      throw http.ClientException('Tapo requires a fixed request length.');
    }
    final body = request.finalize();
    final outgoing = await _client.openUrl(request.method, url);
    outgoing
      ..followRedirects = false
      ..persistentConnection = request.persistentConnection;
    // package:http's IOClient lowercases wire header names. Send canonical
    // names, an explicit length and no compression to reduce firmware quirks.
    void header(String name, Object value) =>
        outgoing.headers.set(name, value, preserveHeaderCase: true);
    header('Host', url.host);
    header('User-Agent', 'SmartLight');
    header('Accept', '*/*');
    header('Accept-Encoding', 'identity');
    header('Connection', request.persistentConnection ? 'keep-alive' : 'close');
    for (final entry in request.headers.entries) {
      final name = entry.key
          .split('-')
          .map(
            (part) =>
                '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
          )
          .join('-');
      header(name, entry.value);
    }
    header('Content-Length', length);
    try {
      await outgoing.addStream(body);
      final response = await outgoing.close();
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name] = values.join(','),
      );
      return http.StreamedResponse(
        response,
        response.statusCode,
        request: request,
        headers: headers,
        contentLength: response.contentLength < 0
            ? null
            : response.contentLength,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      outgoing.abort();
      rethrow;
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
