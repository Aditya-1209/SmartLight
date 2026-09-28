import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'providers/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
