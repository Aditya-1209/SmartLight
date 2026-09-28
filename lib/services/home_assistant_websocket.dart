import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/connection_config.dart';
import '../models/light_entity.dart';

enum RealtimeStatus {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
  unauthorized,
}

typedef SocketFactory = WebSocketChannel Function(Uri uri);

class HomeAssistantWebSocket {
  HomeAssistantWebSocket(
    this.config, {
    SocketFactory? connect,
    this.retryBase = const Duration(seconds: 1),
    this.handshakeTimeout = const Duration(seconds: 12),
    this.heartbeatInterval = const Duration(seconds: 25),
  }) : _connect = connect ?? WebSocketChannel.connect;
  final ConnectionConfig config;
  final SocketFactory _connect;
  final Duration retryBase;
  final Duration handshakeTimeout;
  final Duration heartbeatInterval;
  final _updates = StreamController<LightEntity>.broadcast();
  final _statuses = StreamController<RealtimeStatus>.broadcast();
  Stream<LightEntity> get updates => _updates.stream;
  Stream<RealtimeStatus> get statuses => _statuses.stream;
  RealtimeStatus status = RealtimeStatus.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _deadline;
  Timer? _heartbeat;
  Timer? _pongDeadline;
  bool _disposed = false;
  bool _started = false;
  int _attempt = 0;
  int _generation = 0;
  int _messageId = 1;
  int? _pingId;

  void _status(RealtimeStatus value) {
    status = value;
    if (!_disposed) _statuses.add(value);
  }

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _open();
  }

  Future<void> _open() async {
    if (_disposed) return;
    final generation = ++_generation;
    _status(
      _attempt == 0 ? RealtimeStatus.connecting : RealtimeStatus.reconnecting,
    );
    _deadline = Timer(handshakeTimeout, () => _lost(generation));
    try {
      final channel = _connect(config.websocketUri);
      _channel = channel;
      _subscription = channel.stream.listen(
        (event) => _receive(event, generation),
        onError: (Object _) => _lost(generation),
        onDone: () => _lost(generation),
        cancelOnError: true,
      );
      await channel.ready;
    } catch (_) {
      _lost(generation);
    }
  }

  void _send(Map<String, dynamic> message) =>
      _channel?.sink.add(jsonEncode(message));
  void _receive(dynamic raw, int generation) {
    if (_disposed || generation != _generation) return;
    try {
      final message = jsonDecode(raw as String);
      if (message is! Map<String, dynamic>) return;
      switch (message['type']) {
        case 'auth_required':
          _status(RealtimeStatus.authenticating);
          _send({'type': 'auth', 'access_token': config.token});
        case 'auth_invalid':
          _status(RealtimeStatus.unauthorized);
          ++_generation;
          _closeConnection();
        case 'auth_ok':
          _messageId = 1;
          _send({
            'id': _messageId,
            'type': 'subscribe_events',
            'event_type': 'state_changed',
          });
        case 'result':
          if (message['id'] == 1) {
            if (message['success'] != true) {
              _lost(generation);
              return;
            }
            _deadline?.cancel();
            _attempt = 0;
            _status(RealtimeStatus.connected);
            _heartbeat?.cancel();
            _heartbeat = Timer.periodic(heartbeatInterval, (_) {
              _pingId = ++_messageId;
              _send({'id': _pingId, 'type': 'ping'});
              _pongDeadline?.cancel();
              _pongDeadline = Timer(handshakeTimeout, () => _lost(generation));
            });
          }
        case 'pong':
          if (message['id'] == _pingId) _pongDeadline?.cancel();
        case 'event':
          final event = message['event'];
          if (event is! Map || event['event_type'] != 'state_changed') return;
          final data = event['data'];
          if (data is! Map || data['entity_id'] is! String) return;
          final id = data['entity_id'] as String;
          if (!id.startsWith('light.')) return;
          final newState = data['new_state'];
          if (newState == null) {
            _updates.add(
              LightEntity(
                entityId: id,
                friendlyName: id,
                state: 'unavailable',
                attributes: {},
              ),
            );
          } else if (newState is Map<String, dynamic> &&
              newState['entity_id'] == id) {
            _updates.add(LightEntity.fromJson(newState));
          }
      }
    } catch (_) {
      // Ignore malformed/unrelated events; never log a frame containing credentials.
    }
  }

  void _lost(int generation) {
    if (_disposed ||
        generation != _generation ||
        status == RealtimeStatus.unauthorized) {
      return;
    }
    ++_generation;
    _closeConnection();
    _status(RealtimeStatus.reconnecting);
    final factor = pow(2, min(_attempt++, 5)).toInt();
    _retry?.cancel();
    _retry = Timer(
      Duration(milliseconds: retryBase.inMilliseconds * factor),
      _open,
    );
  }

  void _closeConnection() {
    _deadline?.cancel();
    _heartbeat?.cancel();
    _pongDeadline?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.sink.close().catchError((Object _) {}));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _retry?.cancel();
    _closeConnection();
    unawaited(_updates.close());
    unawaited(_statuses.close());
  }
}
