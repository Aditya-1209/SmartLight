import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_controller.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/diagnostics/diagnostics_screen.dart';
import '../screens/scenes/scenes_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/connection_status.dart';
import 'theme.dart';

class SmartLightApp extends ConsumerWidget {
  const SmartLightApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'SmartLight',
    debugShowCheckedModeBanner: false,
    theme: smartLightTheme(Brightness.light),
    darkTheme: smartLightTheme(Brightness.dark),
    themeMode: ref.watch(appControllerProvider.select((s) => s.settings.theme)),
    home: const AppShell(),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _page = 0;
  final _scroll = ScrollController();
  static const _labels = ['My Room', 'Scenes', 'Diagnostics', 'Settings'];
  static const _icons = [
    Icons.space_dashboard_outlined,
    Icons.auto_awesome_outlined,
    Icons.monitor_heart_outlined,
    Icons.tune,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appControllerProvider.notifier).setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(appControllerProvider.notifier).setForeground(false);
    }
  }

  void _select(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    if (state.loading && !state.configured) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Opening your room…'),
            ],
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final screen = switch (_page) {
      0 => DashboardScreen(
        onSetup: () => _select(3),
        onScenes: () => _select(1),
      ),
      1 => const ScenesScreen(),
      2 => const DiagnosticsScreen(),
      _ => const SettingsScreen(),
    };
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title: const Row(
                children: [
                  Icon(Icons.lightbulb_outline),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text('SmartLight', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              actions: [
                if (state.settings.demo)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Chip(label: Text('Demo')),
                  ),
              ],
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _select,
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(_icons[i]),
                  label: _labels[i],
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 216,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border(
                    right: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'SmartLight',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: NavigationRail(
                        extended: true,
                        minExtendedWidth: 215,
                        backgroundColor: Colors.transparent,
                        selectedIndex: _page,
                        onDestinationSelected: _select,
                        destinations: List.generate(
                          4,
                          (i) => NavigationRailDestination(
                            icon: Icon(_icons[i]),
                            label: Text(_labels[i]),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Icon(
                            state.connected
                                ? Icons.hub_outlined
                                : Icons.cloud_off_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.settings.demo
                                  ? 'Demo workspace'
                                  : state.connected
                                  ? 'Direct Wi-Fi'
                                  : 'Not connected',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (state.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (state.error != null)
                    Container(
                      width: double.infinity,
                      color: scheme.errorContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(state.error!),
                            ),
                          ),
                          TextButton(
                            onPressed: state.loading
                                ? null
                                : () => ref
                                      .read(appControllerProvider.notifier)
                                      .refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  if (state.configured &&
                      state.realtime != ConnectionStatus.connected &&
                      state.error == null)
                    Container(
                      width: double.infinity,
                      color: scheme.secondaryContainer,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Some lights are unavailable. Check their power, Wi-Fi and settings.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: EdgeInsets.all(wide ? 40 : 20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: screen,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
