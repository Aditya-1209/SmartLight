import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../providers/app_controller.dart';
import '../../widgets/brightness_slider.dart';
import '../../widgets/common.dart';
import '../../widgets/design_assets.dart';
import '../../widgets/light_card.dart';
import '../../widgets/scene_card.dart';
import '../device_detail/device_detail_screen.dart';
import '../timers/timers_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onSetup, this.onScenes});
  final VoidCallback onSetup;
  final VoidCallback? onScenes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final mapped = state.slots
        .map(state.lightFor)
        .whereType<LightEntity>()
        .toList();
    final onCount = mapped.where((l) => l.available && l.isOn).length;
    final connected = mapped.where((l) => l.available).length;
    final enabled = state.configured && state.busy.isEmpty && state.connected;
    final dimmable = mapped
        .where((l) => l.supportsBrightness && l.available)
        .toList();
    final brightness = dimmable.isEmpty
        ? 0.0
        : dimmable.map((l) => l.brightnessPercent).reduce((a, b) => a + b) /
              dimmable.length;
    Widget scenes(int count, int columns) => LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: state.scenes
            .take(count)
            .map(
              (scene) => SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: SceneCard(
                  scene: scene,
                  onTap: enabled
                      ? () => runAction(context, controller.applyScene(scene))
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    );
    Widget title(String label, String? action) => Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleLarge)),
        if (action != null)
          TextButton(onPressed: onScenes, child: Text(action)),
      ],
    );
    Widget hero(bool wide) => Container(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 24 : 20,
        vertical: wide ? 24 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.brightness == Brightness.dark
              ? const [Color(0xff2b4233), Color(0xff182920)]
              : const [Color(0xffdbe9d5), Color(0xffeaf1e6)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ROOM BRIGHTNESS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    letterSpacing: .6,
                  ),
                ),
              ),
              IconButton.filled(
                key: ValueKey(onCount > 0 ? 'all-off' : 'all-on'),
                tooltip: onCount > 0
                    ? 'Turn all lights off'
                    : 'Turn all lights on',
                onPressed: enabled
                    ? () => runAction(
                        context,
                        controller.controlAll(LightCommand(on: onCount == 0)),
                      )
                    : null,
                icon: const DesignIcon(
                  'power',
                  color: LightPalette.ink,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${brightness.round()}%',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: wide ? 56 : 40,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text('$onCount lights on', style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(child: RoomIllustration(height: wide ? 114 : 96)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DesignIcon('sun', color: scheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: ValueSlider(
                  key: const ValueKey('master-brightness'),
                  compact: true,
                  label: 'Room brightness',
                  value: brightness,
                  onChanged: enabled && dimmable.isNotEmpty
                      ? (v) => runAction(
                          context,
                          controller.controlAll(
                            LightCommand(brightnessPercent: v),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR SPACE', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      Text('My room.', style: theme.textTheme.headlineLarge),
                      if (wide) ...[
                        const SizedBox(height: 6),
                        const Text('Just the right light for right now.'),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh lights',
                  onPressed: state.loading || !state.configured
                      ? null
                      : controller.refresh,
                  icon: const DesignIcon('more'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: connected > 0
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    state.settings.demo
                        ? '$connected demo lights · Preview mode'
                        : '$connected lights connected',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!state.configured) ...[
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DesignIcon('bulb', size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'One room. All your lights.',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Control your lights on your room’s Wi-Fi. Add a light, or explore with three demo lights.',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: onSetup,
                          child: const Text('Add your lights'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('start-demo'),
                          onPressed: () =>
                              runSetting(context, controller.setDemo(true)),
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Try demo'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: hero(true)),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Make it a moment.',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          scenes(2, 2),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else
              hero(false),
            const SizedBox(height: 20),
            if (state.configured) ...[
              OutlinedButton.icon(
                key: const ValueKey('room-timers'),
                onPressed: () => openTimers(context),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Timers & schedules'),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: Text('Your lights', style: theme.textTheme.titleLarge),
                ),
                Text(
                  '${state.slots.length} devices',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 850
                    ? 3
                    : box.maxWidth >= 550
                    ? 2
                    : 1;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: state.slots.map((slot) {
                    final light = state.lightFor(slot);
                    return SizedBox(
                      width: (box.maxWidth - (columns - 1) * 16) / columns,
                      child: LightCard(
                        slot: slot,
                        light: light,
                        busy: state.busy.contains(slot.id),
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DeviceDetailScreen(slotId: slot.id),
                          ),
                        ),
                        onPower: enabled && light?.available == true
                            ? () => runAction(
                                context,
                                controller.control(
                                  slot,
                                  LightCommand(on: !light!.isOn),
                                ),
                              )
                            : null,
                        onBrightness:
                            enabled &&
                                light?.available == true &&
                                light?.supportsBrightness == true
                            ? (v) => runAction(
                                context,
                                controller.control(
                                  slot,
                                  LightCommand(brightnessPercent: v),
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            title(
              wide ? 'A scene for every mood' : 'Set the mood',
              'All scenes',
            ),
            const SizedBox(height: 16),
            scenes(4, constraints.maxWidth >= 650 ? 4 : 2),
          ],
        );
      },
    );
  }
}
