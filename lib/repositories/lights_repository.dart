import '../models/connection_config.dart';
import '../models/light_command.dart';
import '../models/light_entity.dart';
import '../services/home_assistant_api.dart';
import '../services/home_assistant_websocket.dart';

abstract interface class LightsRepository {
  Stream<LightEntity> get updates;
  Stream<RealtimeStatus> get statuses;
  Future<void> testConnection();
  Future<List<LightEntity>> getLights();
  Future<LightEntity> getLight(String id);
  Future<void> command(LightEntity light, LightCommand command);
  void start();
  void dispose();
}

class HomeAssistantRepository implements LightsRepository {
  HomeAssistantRepository(ConnectionConfig config)
    : _api = HomeAssistantApi(config),
      _socket = HomeAssistantWebSocket(config);
  final HomeAssistantApi _api;
  final HomeAssistantWebSocket _socket;
  @override
  Stream<LightEntity> get updates => _socket.updates;
  @override
  Stream<RealtimeStatus> get statuses => _socket.statuses;
  @override
  Future<void> testConnection() => _api.testConnection();
  @override
  Future<List<LightEntity>> getLights() => _api.getLights();
  @override
  Future<LightEntity> getLight(String id) => _api.getLight(id);
  @override
  Future<void> command(LightEntity light, LightCommand command) =>
      _api.command(light, command);
  @override
  void start() => _socket.start();
  @override
  void dispose() {
    _api.dispose();
    _socket.dispose();
  }
}
