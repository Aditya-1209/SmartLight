import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_light/services/local/tapo_lan_http_client.dart';

void main() {
  http.Request request([String host = '192.168.4.50']) =>
      http.Request('POST', Uri.parse('http://$host/app'))
        ..bodyBytes = [1, 2, 3];

  Future<http.Response> exchange(
    List<String> response, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    server.listen((socket) {
      sockets.add(socket);
      var sent = false;
      socket.listen((_) async {
        if (sent) return;
        sent = true;
        for (final part in response) {
          socket.add(latin1.encode(part));
          await socket.flush();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }, onError: (Object _) {});
    });
    final client = TapoLanHttpClient(
      timeout: timeout,
      connect: (_, _) =>
          Socket.connect(InternetAddress.loopbackIPv4, server.port),
    );
    try {
      return await http.Response.fromStream(await client.send(request()));
    } finally {
      client.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    }
  }

  test('Android LAN transport handles bounded fragmented length and chunked responses', () async {
    final response = await exchange([
      'HTTP/1.1 200 OK\r\nContent-Len',
      'gth: 3\r\nSet-Cookie: test=1\r\n\r\n',
      'a',
      'bc',
    ]);
    expect(response.body, 'abc');
    expect(response.headers['set-cookie'], 'test=1');
    final chunked = await exchange([
      'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n',
      '2\r\nab\r\n',
      '1\r\nc\r\n0\r\n\r\n',
    ]);
    expect(chunked.body, 'abc');
  });

  test('Android LAN transport never follows a redirect', () async {
    final result = await exchange([
      'HTTP/1.1 302 Found\r\nLocation: http://8.8.8.8/app\r\nContent-Length: 0\r\n\r\n',
    ]);
    expect(result.statusCode, 302);
  });

  test(
    'Android LAN transport rejects ambiguous, oversized and malformed framing',
    () async {
      for (final headers in [
        'Content-Length: 65537',
        'Content-Length: -1',
        'Content-Length: 0\r\nContent-Length: 0',
        'Content-Length: 0\r\nTransfer-Encoding: chunked',
        'Transfer-Encoding: gzip',
        'Content-Encoding: gzip\r\nContent-Length: 0',
      ]) {
        await expectLater(
          exchange(['HTTP/1.1 200 OK\r\n$headers\r\n\r\n']),
          throwsFormatException,
        );
      }
      await expectLater(
        exchange([
          'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10001\r\n',
        ]),
        throwsFormatException,
      );
    },
  );

  test('Android LAN transport times out a stalled peer', () async {
    await expectLater(
      exchange([], timeout: const Duration(milliseconds: 40)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('Android transport only opens local IPv4 Tapo POST destinations and rejects header injection', () async {
    var connections = 0;
    final client = TapoLanHttpClient(
      connect: (_, _) async {
        connections++;
        throw StateError('Must not connect');
      },
    );
    addTearDown(client.close);
    for (final url in [
      'http://8.8.8.8/app',
      'http://example.com/app',
      'https://192.168.4.50/app',
      'http://192.168.4.50:8080/app',
      'http://192.168.4.50/other',
      'http://user@192.168.4.50/app',
      'http://127.0.0.1/app',
      'http://[::1]/app',
    ]) {
      await expectLater(
        client.send(http.Request('POST', Uri.parse(url))),
        throwsA(isA<http.ClientException>()),
      );
    }
    final badHeader = request()..headers['Cookie'] = 'a\r\nInjected: yes';
    await expectLater(
      client.send(badHeader),
      throwsA(isA<http.ClientException>()),
    );
    final get = http.Request('GET', Uri.parse('http://192.168.4.50/app'));
    await expectLater(client.send(get), throwsA(isA<http.ClientException>()));
    expect(connections, 0);
  });
}
