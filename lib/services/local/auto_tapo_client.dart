import '../../models/connection_config.dart';
import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../device_exception.dart';
import 'device_client.dart';
import 'tapo_client.dart';
import 'tapo_discovery.dart';

class ResolvedConnection {
  const ResolvedConnection(this.previous, this.current);
  final DeviceConnection previous, current;
}

/// Rediscovers only a previously verified MAC. New/legacy setups choose a light
/// explicitly with Find Tapo light when their old IP no longer works.
class AutoTapoClient implements DeviceClient {
  AutoTapoClient(
    this.config, {
    TapoDiscover? discover,
    DeviceClient Function(DeviceConnection)? factory,
    this.onResolved,
    DateTime Function()? clock,
  }) : _discover = discover ?? TapoDiscovery.discover,
       _factory = factory ?? TapoClient.new,
       _clock = clock ?? DateTime.now {
    _client = _factory(config);
  }
  DeviceConnection config;
  final TapoDiscover _discover;
  final DeviceClient Function(DeviceConnection) _factory;
  final void Function(ResolvedConnection)? onResolved;
  final DateTime Function() _clock;
  final _queue = DeviceQueue();
  late DeviceClient _client;
  DateTime? _lastDiscovery;
  bool _disposed = false;

  void _checkOpen() {
    if (_disposed) {
      throw const DeviceException(
        DeviceError.unavailable,
        'Connection closed.',
      );
    }
  }

  LightEntity _verified(LightEntity light, DeviceConnection candidate) {
    _checkOpen();
    final mac = DeviceConnection.normalizeMac(
      light.rawAttributes['device_mac'],
    );
    if (candidate.macAddress.isNotEmpty && mac != candidate.macAddress) {
      throw const DeviceException(
        DeviceError.unavailable,
        'This address belongs to a different light, or its identity could not be verified.',
      );
    }
    final updated = candidate.withAddress(
      macAddress: mac ?? candidate.macAddress,
    );
    if (updated.host != config.host ||
        updated.macAddress != config.macAddress) {
      final previous = config;
      config = updated;
      onResolved?.call(ResolvedConnection(previous, updated));
    }
    return LightEntity(
      entityId: light.entityId,
      friendlyName: light.friendlyName,
      state: light.state,
      attributes: {
        ...light.rawAttributes,
        'connection_host': config.host,
        'device_mac': config.macAddress,
      },
    );
  }

  Future<LightEntity> _read() async {
    _checkOpen();
    try {
      return _verified(await _client.read(), config);
    } on DeviceException catch (original) {
      _checkOpen();
      if (config.macAddress.isEmpty) {
        if (original.kind == DeviceError.timeout ||
            original.kind == DeviceError.unreachable) {
          throw const DeviceException(
            DeviceError.unreachable,
            'Tapo’s address may have changed. In Settings → Connected lights, choose Find Tapo light and save it once.',
          );
        }
        rethrow;
      }
      if (_lastDiscovery != null &&
          _clock().difference(_lastDiscovery!) < const Duration(seconds: 30)) {
        rethrow;
      }
      _lastDiscovery = _clock();
      final found = await _discover();
      _checkOpen();
      final matches = found
          .where((d) => d.macAddress == config.macAddress)
          .toList();
      // Ambiguous identities never trigger credentials or control requests.
      if (matches.length != 1 || matches.single.host == config.host) {
        rethrow;
      }
      final candidate = config.withAddress(host: matches.single.host);
      final next = _factory(candidate);
      try {
        final light = await next.read();
        final verified = _verified(light, candidate);
        _client.dispose();
        _client = next;
        return verified;
      } catch (_) {
        next.dispose();
        rethrow;
      }
    }
  }

  @override
  Future<LightEntity> read() => _queue.run(_read);

  @override
  Future<void> command(LightEntity light, LightCommand command) => _queue.run(
    () async {
      // Recheck identity before every write, including after a session expires.
      final current = await _read();
      _checkOpen();
      // Never replay an uncertain control request after a network failure.
      await _client.command(current, command);
    },
  );

  @override
  void dispose() {
    _disposed = true;
    _client.dispose();
  }
}
