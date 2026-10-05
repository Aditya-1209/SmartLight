import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/connection_config.dart';
import '../device_exception.dart';
import 'crypto_utils.dart';

class TuyaFrame {
  TuyaFrame(this.sequence, this.command, this.payload);
  final int sequence, command;
  final Uint8List payload;
}

/// Tuya LAN 3.3/3.4/3.5 framing. See THIRD_PARTY_NOTICES.md for references.
class TuyaCodec {
  TuyaCodec(this.version, List<int> key) : key = bytes(key);
  final TuyaVersion version;
  Uint8List key;
  bool get modern => version != TuyaVersion.v33;
  Uint8List versionHeader() => bytes([
    ...ascii.encode(DeviceConnection.versionText(version)),
    ...List.filled(12, 0),
  ]);
  bool _hasVersion(List<int> data) =>
      data.length >= 15 &&
      data[0] == 51 &&
      data[1] == 46 &&
      data[2] >= 51 &&
      data[2] <= 53;
  Uint8List encode(
    int seq,
    int cmd,
    List<int> payload, {
    bool withVersion = false,
    int? returnCode,
    List<int>? nonce,
  }) {
    var body = bytes(payload);
    if (version == TuyaVersion.v35) {
      if (withVersion) body = bytes([...versionHeader(), ...body]);
      if (returnCode != null) body = bytes([...u32(returnCode), ...body]);
      final iv = nonce ?? randomBytes(12);
      final header = bytes([
        ...u32(0x6699),
        0,
        0,
        ...u32(seq),
        ...u32(cmd),
        ...u32(body.length + 28),
      ]);
      return bytes([
        ...header,
        ...iv,
        ...aesGcm(body, key, iv, aad: header.sublist(4)),
        ...u32(0x9966),
      ]);
    }
    if (version == TuyaVersion.v34 && withVersion) {
      body = bytes([...versionHeader(), ...body]);
    }
    // A device may send a completely empty acknowledgement.
    if (body.isNotEmpty) body = aesBlock(body, key);
    if (version == TuyaVersion.v33 && withVersion) {
      body = bytes([...versionHeader(), ...body]);
    }
    if (returnCode != null) body = bytes([...u32(returnCode), ...body]);
    final header = bytes([
      ...u32(0x55aa),
      ...u32(seq),
      ...u32(cmd),
      ...u32(body.length + (modern ? 36 : 8)),
    ]);
    final message = bytes([...header, ...body]);
    return bytes([
      ...message,
      ...modern ? hmac256(key, message) : u32(crc32(message)),
      ...u32(0xaa55),
    ]);
  }

  TuyaFrame decode(List<int> packet, {bool response = true}) {
    final gcm = version == TuyaVersion.v35;
    final headerSize = gcm ? 18 : 16;
    if (packet.length <
            headerSize +
                (gcm
                    ? 32
                    : modern
                    ? 36
                    : 8) ||
        readU32(packet, 0) != (gcm ? 0x6699 : 0x55aa) ||
        readU32(packet, packet.length - 4) != (gcm ? 0x9966 : 0xaa55) ||
        readU32(packet, gcm ? 14 : 12) + headerSize + (gcm ? 4 : 0) !=
            packet.length) {
      throw const FormatException('Invalid Tuya frame.');
    }
    var body = bytes([]);
    if (gcm) {
      body = aesGcm(
        packet.sublist(30, packet.length - 4),
        key,
        packet.sublist(18, 30),
        aad: packet.sublist(4, 18),
        encrypt: false,
      );
    } else {
      final end = packet.length - (modern ? 36 : 8);
      final signed = packet.sublist(0, end);
      final expected = modern ? hmac256(key, signed) : u32(crc32(signed));
      if (!equalBytes(packet.sublist(end, packet.length - 4), expected)) {
        throw const FormatException('Tuya integrity check failed.');
      }
      body = bytes(packet.sublist(16, end));
    }
    if (response) {
      if (body.length < 4) {
        throw const FormatException('Missing Tuya return code.');
      }
      final code = readU32(body, 0);
      if (code != 0) {
        throw DeviceException(
          DeviceError.server,
          'Light rejected the command (code $code).',
        );
      }
      body = body.sublist(4);
    }
    if (!gcm && body.isNotEmpty) {
      if (version == TuyaVersion.v33 && _hasVersion(body)) {
        body = body.sublist(15);
      }
      if (body.isNotEmpty) body = aesBlock(body, key, encrypt: false);
    }
    if (_hasVersion(body)) body = body.sublist(15);
    return TuyaFrame(
      readU32(packet, gcm ? 6 : 4),
      readU32(packet, gcm ? 10 : 8),
      body,
    );
  }
}

/// Bounded parser supports both split frames and several frames in one TCP read.
Stream<Uint8List> tuyaFrames(
  Stream<List<int>> input,
  TuyaVersion version,
) async* {
  var buffer = <int>[];
  final gcm = version == TuyaVersion.v35,
      size = version == TuyaVersion.v35 ? 18 : 16;
  await for (final chunk in input) {
    buffer.addAll(chunk);
    if (buffer.length > 131072) {
      throw const FormatException('Tuya receive buffer too large.');
    }
    while (buffer.length >= size) {
      if (readU32(buffer, 0) != (gcm ? 0x6699 : 0x55aa)) {
        throw const FormatException('Invalid Tuya prefix.');
      }
      final length = readU32(buffer, gcm ? 14 : 12);
      if (length > 65536 || length < (gcm ? 28 : 8)) {
        throw const FormatException('Invalid Tuya length.');
      }
      final total = size + length + (gcm ? 4 : 0);
      if (buffer.length < total) break;
      yield bytes(buffer.sublist(0, total));
      buffer = buffer.sublist(total);
    }
  }
  if (buffer.isNotEmpty) throw const FormatException('Incomplete Tuya frame.');
}

typedef TuyaConnector = Future<Socket> Function(String host, int port);

enum TuyaConnectionStage { connecting, handshake, status, control }

class TuyaTimeoutException extends DeviceException {
  const TuyaTimeoutException(this.stage)
    : super(
        stage == TuyaConnectionStage.connecting
            ? DeviceError.unreachable
            : DeviceError.timeout,
        stage == TuyaConnectionStage.connecting
            ? 'TCP connection timed out. Check the light’s IP, power and Wi-Fi.'
            : stage == TuyaConnectionStage.handshake
            ? 'TCP connected, but the session handshake timed out.'
            : stage == TuyaConnectionStage.status
            ? 'TCP connected, but the status request timed out.'
            : 'TCP connected, but the control request timed out.',
      );
  final TuyaConnectionStage stage;
}

class TuyaTransport {
  TuyaTransport(
    this.config, {
    TuyaConnector? connector,
    this.timeout = const Duration(seconds: 6),
  }) : _connector =
           connector ??
           ((host, port) => Socket.connect(host, port, timeout: timeout));
  final DeviceConnection config;
  final TuyaConnector _connector;
  final Duration timeout;
  Socket? _socket;
  bool _disposed = false;
  bool _device22 = false;
  DateTime? _authRetryAt;

  Future<Map<String, dynamic>> exchange({Map<String, dynamic>? dps}) async {
    if (_disposed) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Connection closed.',
      );
    }
    if (_authRetryAt != null && DateTime.now().isBefore(_authRetryAt!)) {
      throw const DeviceException(
        DeviceError.unauthorized,
        'Check the local key and protocol version; authentication can be retried in a minute.',
      );
    }
    StreamIterator<Uint8List>? incoming;
    var stage = TuyaConnectionStage.connecting;
    try {
      final socket = await _connector(config.host, 6668).timeout(timeout);
      if (_disposed) {
        socket.destroy();
        throw const DeviceException(
          DeviceError.unavailable,
          'Connection closed.',
        );
      }
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      incoming = StreamIterator(tuyaFrames(socket, config.version));
      final codec = TuyaCodec(config.version, utf8.encode(config.localKey));
      var seq = 1;
      Future<TuyaFrame> receive(
        Set<int> commands, {
        bool allowEmpty = false,
      }) async {
        final deadline = DateTime.now().add(timeout);
        for (var n = 0; n < 16; n++) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining.isNegative ||
              !await incoming!.moveNext().timeout(remaining)) {
            throw TimeoutException('No light response.');
          }
          final frame = codec.decode(incoming!.current);
          if (commands.contains(frame.command) &&
              (allowEmpty || frame.payload.isNotEmpty)) {
            return frame;
          }
        }
        throw const FormatException('Too many unrelated Tuya responses.');
      }

      void send(int cmd, List<int> payload, {bool version = false}) {
        socket.add(codec.encode(seq++, cmd, payload, withVersion: version));
      }

      if (codec.modern) {
        stage = TuyaConnectionStage.handshake;
        final local = randomBytes(16);
        send(3, local);
        final reply = (await receive({4})).payload;
        if (reply.length != 48 ||
            !equalBytes(reply.sublist(16), hmac256(codec.key, local))) {
          _authRetryAt = DateTime.now().add(const Duration(minutes: 1));
          throw const DeviceException(
            DeviceError.unauthorized,
            'The light rejected its local key. Re-pairing changes this key.',
          );
        }
        final remote = reply.sublist(0, 16);
        send(5, hmac256(codec.key, remote));
        final mixed = List.generate(16, (i) => local[i] ^ remote[i]);
        codec.key = config.version == TuyaVersion.v35
            ? aesGcm(mixed, codec.key, local.sublist(0, 12)).sublist(0, 16)
            : aesBlock(mixed, codec.key, padding: false);
      }
      stage = dps == null
          ? TuyaConnectionStage.status
          : TuyaConnectionStage.control;
      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      Future<Map<String, dynamic>> request() async {
        final query = dps == null;
        final cmd = query
            ? (_device22
                  ? 13
                  : codec.modern
                  ? 16
                  : 10)
            : codec.modern
            ? 13
            : 7;
        final requested = config.profile == TuyaProfile.modern
            ? ['20', '21', '22', '23', '24']
            : ['1', '2', '3', '4', '5'];
        final payload = query && !_device22 && codec.modern
            ? <String, dynamic>{}
            : !query && codec.modern
            ? <String, dynamic>{
                'protocol': 5,
                't': time,
                'data': {'dps': dps},
              }
            : <String, dynamic>{
                'devId': config.deviceId,
                'uid': config.deviceId,
                if (query && !_device22) 'gwId': config.deviceId,
                't': '$time',
                if (!query) 'dps': dps,
                if (query && _device22)
                  'dps': {for (final dp in requested) dp: null},
              };
        send(
          cmd,
          utf8.encode(jsonEncode(payload)),
          version: cmd == 7 || cmd == 13,
        );
        final reply = await receive({cmd, 8}, allowEmpty: !query);
        if (reply.payload.isEmpty) return {};
        final text = utf8.decode(reply.payload);
        if (text.contains('data unvalid') && query && !_device22) {
          _device22 = true;
          return request();
        }
        final value = jsonDecode(text);
        if (value is! Map) throw const FormatException('Invalid light status.');
        if (value['error'] != null ||
            value['Error'] != null ||
            (value['success'] == false)) {
          throw const DeviceException(
            DeviceError.server,
            'The light rejected the request. Check its protocol version and light profile.',
          );
        }
        final data = value['data'] is Map ? value['data'] as Map : value;
        for (final source in [value, data]) {
          for (final field in ['gwId', 'devId']) {
            final id = source[field];
            if (id != null && id != config.deviceId) {
              throw const DeviceException(
                DeviceError.unauthorized,
                'This address belongs to a different light.',
              );
            }
          }
        }
        return data['dps'] is Map
            ? Map<String, dynamic>.from(data['dps'] as Map)
            : {};
      }

      return await request();
    } catch (error) {
      if (error is DeviceException) rethrow;
      if (error is TimeoutException) {
        throw TuyaTimeoutException(stage);
      }
      if (error is SocketException) {
        throw DeviceException(
          stage == TuyaConnectionStage.connecting
              ? DeviceError.unreachable
              : DeviceError.malformed,
          stage == TuyaConnectionStage.connecting
              ? 'Cannot reach this light. Join the same Wi-Fi and check its power and IP address.'
              : 'The light closed its TCP connection before a usable reply. Check its local key and protocol version.',
        );
      }
      _authRetryAt = DateTime.now().add(const Duration(minutes: 1));
      throw const DeviceException(
        DeviceError.malformed,
        'Cannot decode the light’s reply. Check its local key and protocol version.',
      );
    } finally {
      _socket?.destroy();
      _socket = null;
      if (incoming != null) await incoming.cancel();
    }
  }

  void dispose() {
    _disposed = true;
    _socket?.destroy();
  }
}
