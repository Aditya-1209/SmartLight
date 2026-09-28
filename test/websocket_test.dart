import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/services/home_assistant_websocket.dart';

void main() {
  late HttpServer server;
  late List<WebSocket> sockets;
  late HomeAssistantWebSocket client;
  late List<Map<String, dynamic>> received;
  late List<RealtimeStatus> statuses;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sockets = [];
    received = [];
    statuses = [];
    server.transform(WebSocketTransformer()).listen((socket) {
      sockets.add(socket);
      socket.add(jsonEncode({'type': 'auth_required'}));
      socket.listen((raw) {
        received.add(jsonDecode(raw as String) as Map<String, dynamic>);
      });
    });
    client = HomeAssistantWebSocket(
      ConnectionConfig('http://127.0.0.1:${server.port}', 'test-token'),
      retryBase: const Duration(milliseconds: 15),
    );
    client.statuses.listen(statuses.add);
  });
  tearDown(() async {
    client.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  });
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for socket state');
  }

  Future<void> authenticate() async {
    client.start();
    await until(() => received.isNotEmpty);
    expect(received.first, {'type': 'auth', 'access_token': 'test-token'});
    sockets.last.add(jsonEncode({'type': 'auth_ok'}));
    await until(() => received.length >= 2);
    expect(received[1], {
      'id': 1,
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
    sockets.last.add(jsonEncode({'id': 1, 'type': 'result', 'success': true}));
    await until(() => statuses.contains(RealtimeStatus.connected));
  }

  test('auth, subscription, events, malformed frames and removal', () async {
    final updates = <String>[];
    client.updates.listen(
      (light) => updates.add('${light.entityId}:${light.state}'),
    );
    await authenticate();
    sockets.last.add('invalid json');
    sockets.last.add('[]');
    sockets.last.add(
      jsonEncode({
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {'entity_id': 'sensor.temp', 'new_state': null},
        },
      }),
    );
    for (final next in [
      <String, dynamic>{
        'entity_id': 'light.test',
        'state': 'on',
        'attributes': {},
      },
      null,
    ]) {
      sockets.last.add(
        jsonEncode({
          'type': 'event',
          'event': {
            'event_type': 'state_changed',
            'data': {'entity_id': 'light.test', 'new_state': next},
          },
        }),
      );
    }
    await until(() => updates.length == 2);
    expect(updates, ['light.test:on', 'light.test:unavailable']);
  });
  test(
    'auth failure stops reconnect and duplicate starts are ignored',
    () async {
      client.start();
      client.start();
      await until(() => received.isNotEmpty);
      sockets.single.add(jsonEncode({'type': 'auth_invalid'}));
      await until(() => statuses.contains(RealtimeStatus.unauthorized));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(sockets.length, 1);
    },
  );
  test(
    'dropped connection reconnects and disposal prevents further connections',
    () async {
      await authenticate();
      await sockets.first.close();
      await until(() => sockets.length == 2);
      expect(statuses, contains(RealtimeStatus.reconnecting));
      client.dispose();
      await sockets.last.close();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(sockets.length, 2);
    },
  );
  test('handshake timeout triggers reconnect', () async {
    client.dispose();
    client = HomeAssistantWebSocket(
      ConnectionConfig('http://127.0.0.1:${server.port}', 'test-token'),
      retryBase: const Duration(milliseconds: 10),
      handshakeTimeout: const Duration(milliseconds: 25),
    );
    client.start();
    await until(() => sockets.length >= 2);
  });
}
