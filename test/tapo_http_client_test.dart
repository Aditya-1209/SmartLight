import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_light/models/light_command.dart';
import 'package:smart_light/services/local/crypto_utils.dart';
import 'package:smart_light/services/local/tapo_client.dart';
import 'package:smart_light/services/local/tapo_http_client.dart';
import 'package:smart_light/services/local/tapo_lan_http_client.dart';

import 'support.dart';

void main() {
  for (final lanSocket in [false, true]) {
    test(
      'Tapo HTTP wire framing, KLAP session, cookie and command (LAN socket: $lanSocket)',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        final handlers = <Future<void>>[];
        final failures = <Object>[];
        final headersSeen = <String>[];
        final config = tapoConfig();
        final auth = sha256([
          ...sha1(utf8.encode(config.email)),
          ...sha1(utf8.encode(config.password)),
        ]);
        final remote = List.generate(16, (i) => 16 + i);
        List<int>? local;
        KlapCipher? cipher;
        var on = true;
        server.listen((socket) {
          sockets.add(socket);
          handlers.add(() async {
            var buffer = <int>[];
            try {
              await for (final chunk in socket) {
                buffer.addAll(chunk);
                while (true) {
                  final text = latin1.decode(buffer);
                  final end = text.indexOf('\r\n\r\n');
                  if (end < 0) break;
                  final header = text.substring(0, end);
                  final length = int.parse(
                    RegExp(
                      r'^content-length: (\d+)$',
                      caseSensitive: false,
                      multiLine: true,
                    ).firstMatch(header.replaceAll('\r', ''))!.group(1)!,
                  );
                  if (buffer.length < end + 4 + length) break;
                  final body = buffer.sublist(end + 4, end + 4 + length);
                  buffer = buffer.sublist(end + 4 + length);
                  headersSeen.add(header);
                  expect(header, contains('\r\nHost: ${config.host}\r\n'));
                  expect(header, contains('\r\nContent-Length: $length'));
                  expect(
                    header,
                    contains('\r\nContent-Type: application/octet-stream'),
                  );
                  expect(header, contains('\r\nAccept-Encoding: identity'));
                  expect(
                    header,
                    contains(
                      lanSocket
                          ? '\r\nConnection: close'
                          : '\r\nConnection: keep-alive',
                    ),
                  );
                  expect(
                    header.toLowerCase(),
                    isNot(contains('transfer-encoding')),
                  );
                  final uri = Uri.parse(header.split(' ')[1]);
                  List<int> response;
                  var cookieHeader = '';
                  if (uri.path == '/app/handshake1') {
                    expect(length, 16);
                    local = body;
                    cipher = KlapCipher(local!, remote, auth);
                    response = [
                      ...remote,
                      ...sha256([...local!, ...remote, ...auth]),
                    ];
                    cookieHeader =
                        'Set-Cookie: TP_SESSIONID=wire-test;TIMEOUT=86400\r\n';
                  } else {
                    expect(
                      header,
                      contains('\r\nCookie: TP_SESSIONID=wire-test'),
                    );
                    if (uri.path == '/app/handshake2') {
                      expect(body, sha256([...remote, ...local!, ...auth]));
                      response = [];
                    } else {
                      expect(uri.path, '/app/request');
                      final seq = int.parse(uri.queryParameters['seq']!);
                      cipher!.sequence = seq;
                      final data =
                          jsonDecode(utf8.decode(cipher!.decrypt(body))) as Map;
                      if (data['method'] == 'set_device_info') {
                        on = (data['params'] as Map)['device_on'] as bool;
                      }
                      cipher!.sequence = seq - 1;
                      response = cipher!.encrypt(
                        utf8.encode(
                          jsonEncode({
                            'error_code': 0,
                            'result': data['method'] == 'get_device_info'
                                ? {'device_on': on, 'brightness': 60}
                                : {},
                          }),
                        ),
                      );
                    }
                  }
                  socket.add(
                    ascii.encode(
                      'HTTP/1.1 200 OK\r\n'
                      'Content-Length: ${response.length}\r\n'
                      '${cookieHeader}Connection: keep-alive\r\n\r\n',
                    ),
                  );
                  socket.add(response);
                  await socket.flush();
                }
              }
            } catch (error) {
              failures.add(error);
              socket.destroy();
            }
          }());
        });
        final client = TapoClient(
          config,
          clientFactory: () {
            if (lanSocket) {
              return TapoLanHttpClient(
                connect: (_, _) =>
                    Socket.connect(InternetAddress.loopbackIPv4, server.port),
              );
            }
            final native = HttpClient()
              ..connectionFactory = (_, _, _) => Socket.startConnect(
                InternetAddress.loopbackIPv4,
                server.port,
              );
            return TapoHttpClient(client: native);
          },
        );
        addTearDown(() async {
          client.dispose();
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
          await Future.wait(handlers);
          expect(failures, isEmpty);
        });
        final light = await client.read();
        expect(light.isOn, true);
        await client.command(light, const LightCommand(on: false));
        expect((await client.read()).isOn, false);
        expect(headersSeen, hasLength(5));
        expect(sockets, hasLength(lanSocket ? 5 : 1));
      },
    );
  }

  test(
    'Tapo HTTP refuses redirects even when the caller enables them',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var calls = 0;
      server.listen((request) async {
        calls++;
        await request.drain<void>();
        request.response
          ..statusCode = 302
          ..headers.set('Location', 'http://192.168.1.51/app');
        await request.response.close();
      });
      final native = HttpClient()
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
      final client = TapoHttpClient(client: native);
      addTearDown(client.close);
      final request = http.Request('POST', Uri.parse('http://192.168.1.50/app'))
        ..bodyBytes = [1, 2, 3];
      final response = await client.send(request);
      await response.stream.drain<void>();
      expect(response.statusCode, 302);
      expect(calls, 1);
    },
  );

  test(
    'Tapo HTTP refuses non-local destinations before opening a socket',
    () async {
      var connections = 0;
      final native = HttpClient()
        ..connectionFactory = (_, _, _) {
          connections++;
          throw StateError('Must not connect');
        };
      final client = TapoHttpClient(client: native);
      addTearDown(client.close);
      for (final target in [
        'http://example.com/app',
        'http://8.8.8.8/app',
        'https://192.168.1.50/app',
        'http://192.168.1.50:8080/app',
      ]) {
        await expectLater(
          client.send(http.Request('POST', Uri.parse(target))),
          throwsA(isA<http.ClientException>()),
        );
      }
      expect(connections, 0);
    },
  );
}
