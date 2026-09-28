import '../../models/light_command.dart';
import '../../models/light_entity.dart';

abstract interface class DeviceClient {
  Future<LightEntity> read();
  Future<void> command(LightEntity light, LightCommand command);
  void dispose();
}

/// One queue per physical device prevents polling from racing encrypted commands.
class DeviceQueue {
  Future<void>? _tail;
  Future<T> run<T>(Future<T> Function() action) {
    final next = (_tail ?? Future<void>.value()).then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
