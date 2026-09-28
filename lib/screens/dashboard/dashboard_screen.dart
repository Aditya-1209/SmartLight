import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../models/scene.dart';
import '../../providers/app_controller.dart';
import '../../widgets/brightness_slider.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/light_card.dart';
import '../../widgets/scene_card.dart';
import '../device_detail/device_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onSetup});
  final VoidCallback onSetup;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final mapped = state.slots
        .map(state.lightFor)
        .whereType<LightEntity>()
        .toList();
    final onCount = mapped.where((light) => light.isOn == true).length;
    final enabled = state.configured && state.busy.isEmpty && state.connected;
    final dimmable = mapped
        .where(
          (light) =>
              light.supportsBrightness == true && light.available == true,
        )
        .toList();
    final brightness = dimmable.isEmpty
        ? 0.0
        : dimmable.map((l) => l.brightnessPercent).reduce((a, b) => a + b) /
              dimmable.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'My Room',
          state.configured
              ? '$onCount lights on · Make yourself at home.'
              : 'Your room, in sync. Let’s connect your lights.',
          trailing: IconButton(
            tooltip: 'Refresh lights',
            onPressed: state.loading || !state.configured
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (!state.configured) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 44),
                const SizedBox(height: 18),
                Text(
                  'One room. All your lights.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Control your lights directly on your room’s Wi-Fi. Add a light to get started, or explore with three demo lights.',
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
          const SizedBox(height: 24),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wb_sunny_outlined, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'The whole room',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (state.settings.demo) const StatusBadge('Demo'),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('all-on'),
                      onPressed: enabled
                          ? () => runAction(
                              context,
                              controller.controlAll(const LightCommand()),
                            )
                          : null,
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('All on'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('all-off'),
                      onPressed: enabled
                          ? () => runAction(
                              context,
                              controller.controlAll(
                                const LightCommand(on: false),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.nights_stay_outlined),
                      label: const Text('All off'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ValueSlider(
                  key: const ValueKey('master-brightness'),
                  label: 'Master brightness',
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
                if (mapped.any((l) => l.supportsRgb == true)) ...[
                  const SizedBox(height: 12),
                  const Text('A touch of color'),
                  const SizedBox(height: 12),
                  LightColorPicker(
                    custom: false,
                    onSelected: enabled
                        ? (rgb) => runAction(
                            context,
                            controller.controlAll(LightCommand(rgb: rgb)),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
        Text('Your lights', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 3
                : constraints.maxWidth >= 550
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: state.slots.map((slot) {
                final light = state.lightFor(slot);
                return SizedBox(
                  width: width,
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
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 30),
        Text('Set the mood', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 4 : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: LightScene.defaults
                  .map(
                    (scene) => SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 12) / columns,
                      child: SceneCard(
                        scene: scene,
                        onTap: enabled
                            ? () => runAction(
                                context,
                                controller.applyScene(scene),
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
