import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'providers/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'SmartLight local protocols',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final container = ProviderContainer();
  final initialization = container
      .read(appControllerProvider.notifier)
      .initialize();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SmartLightApp(),
    ),
  );
  await initialization;
}
