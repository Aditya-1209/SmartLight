import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_controller.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../widgets/design_assets.dart';
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
  static const _labels = ['My room', 'Scenes', 'Settings'];
  static const _icons = ['room', 'scenes', 'settings'];
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
        onSetup: () => _select(2),
        onScenes: () => _select(1),
      ),
      1 => const ScenesScreen(),
      _ => const SettingsScreen(),
    };
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _select,
              destinations: List.generate(
                3,
                (i) => NavigationDestination(
                  icon: DesignIcon(
                    _icons[i],
                    color: _page == i
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  label: _labels[i],
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 224,
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
                          DesignIcon('bulb', color: scheme.primary),
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
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          for (var i = 0; i < _labels.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: _page == i
                                    ? scheme.surfaceContainerHighest
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  selected: _page == i,
                                  selectedColor: scheme.primary,
                                  leading: DesignIcon(
                                    _icons[i],
                                    size: 20,
                                    color: _page == i
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    _labels[i],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  onTap: () => _select(i),
                                ),
                              ),
                            ),
                        ],
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
                                  ? 'Local connection'
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
                        padding: EdgeInsets.fromLTRB(
                          wide ? 40 : 20,
                          wide ? 40 : 24,
                          wide ? 40 : 20,
                          28,
                        ),
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
