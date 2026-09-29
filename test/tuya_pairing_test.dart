import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_light/models/connection_config.dart';
import 'package:smart_light/services/pairing/tuya_pairing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartlight/tuya_pairing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'pairing details reject public hosts and do not guess unknown protocols',
    () {
      final result = PairedTuyaDevice.fromMap({
        'deviceId': 'test-light',
        'localKey': '0123456789abcdef',
        'host': '223.185.128.1',
        'version': '2.2',
        'dpIds': ['20', '21'],
      });
      expect(result.host, isEmpty);
      expect(result.version, isNull);
      expect(result.profile, TuyaProfile.modern);
      expect(result.hasLocalKey, isTrue);
      expect(result.toString(), isNot(contains('0123456789abcdef')));
    },
  );

  test('pairing requires a 16-byte local key, not a 16-character key', () {
    expect(
      PairedTuyaDevice.fromMap({'deviceId': 'test', 'localKey': 'é' * 16})
          .hasLocalKey,
      isFalse,
    );
    expect(
      PairedTuyaDevice.fromMap({'localKey': '0123456789abcdef'}).hasLocalKey,
      isFalse,
    );
    final device = PairedTuyaDevice.fromMap({
      'deviceId': 'test',
      'localKey': '0123456789abcdef',
      'host': '192.168.4.50',
      'version': '3.4',
      'dpIds': [1, 2],
    });
    expect(device.host, '192.168.4.50');
    expect(device.version, TuyaVersion.v34);
    expect(device.profile, TuyaProfile.legacy);
  });

  test('a failed setup retry reuses the persisted pairing identity', () async {
    final profiles = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') {
        profiles.add(Map.of(call.arguments as Map));
        if (profiles.length == 1) throw PlatformException(code: 'timeout');
        return <dynamic>[];
      }
      return null;
    });
    await expectLater(
      TuyaPairing().prepare(),
      throwsA(isA<PlatformException>()),
    );
    await TuyaPairing().prepare();
    expect(profiles[0], profiles[1]);
    expect((profiles[0]['uid'] as String).length, 48);
    expect(profiles[0]['uid'], isNot(profiles[0]['password']));
  });

  test('permission denial prevents requesting a pairing token', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'permission');
    });
    await expectLater(
      TuyaPairing().prepareToken(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, ['permissions']);
  });

  test('builds without the SDK report pairing unavailable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await TuyaPairing().available(), isFalse);
  });
}
