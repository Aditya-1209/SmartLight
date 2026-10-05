import '../../models/connection_config.dart';

class ResolvedConnection {
  const ResolvedConnection(this.previous, this.current);
  final DeviceConnection previous, current;
}
