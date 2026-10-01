import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/connection_config.dart';

/// Dedicated Android LAN transport: Android's XML HTTP exceptions cannot follow
/// DHCP addresses. Keep global cleartext denied; permit only Tapo POST endpoints
/// at numeric private IPv4 addresses here. Tapo encrypts/authenticates payloads.
/// No DNS, proxies, redirects or general-purpose HTTP access.
class TapoLanHttpClient extends http.BaseClient {
  TapoLanHttpClient({
    this.timeout = const Duration(seconds: 8),
    Future<Socket> Function(String host, int port)? connect,
  }) : _connect =
           connect ??
           ((host, port) =>
               Socket.connect(InternetAddress(host), port, timeout: timeout));
  final Duration timeout;
  final Future<Socket> Function(String, int) _connect;
  final _sockets = <Socket>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final length = request.contentLength;
    if (_closed ||
        request.method != 'POST' ||
        uri.scheme != 'http' ||
        uri.port != 80 ||
        !DeviceConnection.isLocalAddress(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !{
          '/app',
          '/app/handshake1',
          '/app/handshake2',
          '/app/request',
        }.contains(uri.path) ||
        length == null ||
        length < 0 ||
        length > 65536) {
      throw http.ClientException('Tapo requires a bounded local IPv4 request.');
    }
    final headers = <String, String>{};
    for (final entry in request.headers.entries) {
      final name = switch (entry.key.toLowerCase()) {
        'content-type' => 'Content-Type',
        'cookie' => 'Cookie',
        _ => null,
      };
      if (name == null ||
          !RegExp(r'^[\x20-\x7E]*$').hasMatch(entry.value) ||
          entry.value.length > 4096) {
        throw http.ClientException('Invalid Tapo request header.');
      }
      headers[name] = entry.value;
    }
    final body = BytesBuilder(copy: false);
    await for (final part in request.finalize().timeout(timeout)) {
      if (body.length + part.length > length) {
        throw http.ClientException('Invalid Tapo request length.');
      }
      body.add(part);
    }
    if (body.length != length) {
      throw http.ClientException('Invalid Tapo request length.');
    }
    final socket = await _connect(uri.host, 80);
    if (_closed) {
      socket.destroy();
      throw http.ClientException('Connection closed.');
    }
    _sockets.add(socket);
    final reader = _LanResponseReader(socket, timeout);
    try {
      final target = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      socket.add(
        ascii.encode(
          'POST $target HTTP/1.1\r\nHost: ${uri.host}\r\n'
          'User-Agent: SmartLight\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n'
          '${headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()}'
          'Content-Length: $length\r\n\r\n',
        ),
      );
      socket.add(body.takeBytes());
      return await (() async {
        await socket.flush();
        return reader.response(request);
      })().timeout(timeout);
    } finally {
      socket.destroy();
      _sockets.remove(socket);
      await reader.close();
    }
  }

  @override
  void close() {
    _closed = true;
    for (final socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
  }
}

class _LanResponseReader {
  _LanResponseReader(Socket socket, Duration timeout)
    : _input = StreamIterator(socket.timeout(timeout));
  final StreamIterator<List<int>> _input;
  List<int> _buffer = [];
  int _offset = 0, _total = 0;
  Future<bool> _more() async {
    if (_offset < _buffer.length) return true;
    if (!await _input.moveNext()) return false;
    _buffer = _input.current;
    _offset = 0;
    _total += _buffer.length;
    if (_total > 98304) {
      throw const FormatException('Oversized Tapo HTTP response.');
    }
    return true;
  }

  Future<List<int>> take(int count) async {
    final out = BytesBuilder(copy: false);
    while (count > 0) {
      if (!await _more()) {
        throw const FormatException('Truncated Tapo HTTP response.');
      }
      final n = count < _buffer.length - _offset
          ? count
          : _buffer.length - _offset;
      out.add(_buffer.sublist(_offset, _offset + n));
      _offset += n;
      count -= n;
    }
    return out.takeBytes();
  }

  Future<String> line() async {
    final bytes = <int>[];
    while (bytes.length < 8192) {
      bytes.add((await take(1)).single);
      if (bytes.length >= 2 &&
          bytes[bytes.length - 2] == 13 &&
          bytes.last == 10) {
        return ascii.decode(bytes.sublist(0, bytes.length - 2));
      }
    }
    throw const FormatException('Oversized HTTP header.');
  }

  Future<http.StreamedResponse> response(http.BaseRequest request) async {
    final status = RegExp(r'^HTTP/1\.[01] ([2-5][0-9]{2})(?: .*)?$')
        .firstMatch(await line());
    if (status == null) {
      throw const FormatException('Invalid Tapo HTTP status.');
    }
    final headers = <String, String>{};
    var headerBytes = 0;
    while (true) {
      final text = await line();
      headerBytes += text.length + 2;
      if (headerBytes > 16384) {
        throw const FormatException('Oversized HTTP headers.');
      }
      if (text.isEmpty) break;
      final colon = text.indexOf(':');
      if (colon <= 0 || text.startsWith(' ') || text.startsWith('\t')) {
        throw const FormatException('Invalid HTTP header.');
      }
      final name = text.substring(0, colon).toLowerCase();
      if (headers.containsKey(name)) {
        throw const FormatException('Duplicate HTTP header.');
      }
      headers[name] = text.substring(colon + 1).trim();
    }
    if (headers.containsKey('transfer-encoding') &&
        headers.containsKey('content-length')) {
      throw const FormatException('Ambiguous HTTP framing.');
    }
    if (headers.containsKey('content-encoding') &&
        headers['content-encoding'] != 'identity') {
      throw const FormatException('Compressed HTTP response.');
    }
    final body = BytesBuilder(copy: false);
    final transfer = headers['transfer-encoding'];
    if (transfer != null) {
      if (transfer.toLowerCase() != 'chunked') {
        throw const FormatException('Unsupported HTTP framing.');
      }
      while (true) {
        final size = int.tryParse((await line()).split(';').first, radix: 16);
        if (size == null || size < 0 || body.length + size > 65536) {
          throw const FormatException('Oversized HTTP body.');
        }
        if (size == 0) {
          var trailerBytes = 0;
          while (true) {
            final trailer = await line();
            trailerBytes += trailer.length + 2;
            if (trailerBytes > 8192) {
              throw const FormatException('Oversized HTTP trailer.');
            }
            if (trailer.isEmpty) break;
          }
          break;
        }
        body.add(await take(size));
        if (await line() != '') {
          throw const FormatException('Invalid HTTP chunk.');
        }
      }
    } else if (headers.containsKey('content-length')) {
      final rawLength = headers['content-length']!;
      final size = RegExp(r'^\d+$').hasMatch(rawLength)
          ? int.tryParse(rawLength)
          : null;
      if (size == null || size > 65536) {
        throw const FormatException('Oversized HTTP body.');
      }
      body.add(await take(size));
    } else {
      while (await _more()) {
        if (body.length + _buffer.length - _offset > 65536) {
          throw const FormatException('Oversized HTTP body.');
        }
        body.add(_buffer.sublist(_offset));
        _offset = _buffer.length;
      }
    }
    final bytes = body.takeBytes();
    return http.StreamedResponse(
      Stream.value(bytes),
      int.parse(status[1]!),
      headers: headers,
      contentLength: bytes.length,
      request: request,
      persistentConnection: false,
    );
  }

  Future<void> close() => _input.cancel();
}
