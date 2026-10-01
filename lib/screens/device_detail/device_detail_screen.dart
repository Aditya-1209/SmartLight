import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/light_command.dart';
import '../../providers/app_controller.dart';
import '../../widgets/brightness_slider.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/design_assets.dart';
import '../scenes/scene_editor_screen.dart';

class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({required this.slotId, super.key});
  final String slotId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final slot = state.slots.singleWhere((s) => s.id == slotId);
    final light = state.lightFor(slot);
    final enabled =
        light?.available == true && state.connected && state.busy.isEmpty;
    final theme = Theme.of(context);
    final colour =
        light?.rgbColor != null &&
        light?.rawAttributes['color_mode'] != 'color_temp';
    final accent = colour ? materialColor(light!.rgbColor!) : LightPalette.warm;
    void send(LightCommand command) =>
        runAction(context, controller.control(slot, command));
    return Scaffold(
      appBar: AppBar(
        title: Text(slot.name),
        actions: [
          IconButton(
            onPressed: state.loading ? null : controller.refresh,
            tooltip: 'Refresh light',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: light?.available == true
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    light?.available == true
                        ? 'Connected'
                        : light == null
                        ? 'Add this light in Settings'
                        : 'Unavailable',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              SectionCard(
                child: Column(
                  children: [
                    SizedBox(
                      height: 100,
                      child: Center(
                        child: slotId == 'strip'
                            ? DesignIcon(
                                'strip',
                                size: 72,
                                color: light?.isOn == true
                                    ? accent
                                    : theme.colorScheme.outline,
                              )
                            : FractionallySizedBox(
                                widthFactor: .8,
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: light?.isOn == true
                                        ? accent
                                        : theme.colorScheme.outline,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: light?.isOn == true
                                        ? [
                                            BoxShadow(
                                              color: accent.withValues(
                                                alpha: .25,
                                              ),
                                              blurRadius: 24,
                                              spreadRadius: 10,
                                            ),
                                          ]
                                        : [],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            light?.isOn == true
                                ? 'Light is on'
                                : 'Light is off',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Switch(
                          key: const ValueKey('detail-power'),
                          value: light?.isOn ?? false,
                          onChanged: enabled
                              ? (on) => send(LightCommand(on: on))
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (light?.supportsBrightness == true) ...[
                const SizedBox(height: 20),
                SectionCard(
                  child: ValueSlider(
                    key: const ValueKey('detail-brightness'),
                    label: 'Brightness',
                    color: accent,
                    value: light!.brightnessPercent.toDouble(),
                    onChanged: enabled
                        ? (v) => send(LightCommand(brightnessPercent: v))
                        : null,
                  ),
                ),
              ],
              if (light?.supportsTemperature == true) ...[
                const SizedBox(height: 20),
                SectionCard(
                  child: Column(
                    children: [
                      ValueSlider(
                        label: 'White temperature',
                        suffix: ' K',
                        value: (light!.colorTempKelvin ?? 4000).toDouble(),
                        min: light.minColorTempKelvin.toDouble(),
                        max: light.maxColorTempKelvin.toDouble(),
                        onChanged:
                            enabled &&
                                light.maxColorTempKelvin >
                                    light.minColorTempKelvin
                            ? (v) => send(LightCommand(kelvin: v.round()))
                            : null,
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text('Warm'), Text('Cool')],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in {
                            'Warm': light.minColorTempKelvin,
                            'Neutral':
                                ((light.minColorTempKelvin +
                                            light.maxColorTempKelvin) /
                                        2)
                                    .round(),
                            'Cool': light.maxColorTempKelvin,
                          }.entries)
                            ChoiceChip(
                              label: Text(item.key),
                              selected:
                                  light.colorTempKelvin == item.value &&
                                  !colour,
                              onSelected: enabled
                                  ? (_) =>
                                        send(LightCommand(kelvin: item.value))
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (light?.supportsRgb == true) ...[
                const SizedBox(height: 20),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Colour', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      LightColorPicker(
                        current: light!.rgbColor,
                        onSelected: enabled
                            ? (rgb) => send(LightCommand(rgb: rgb))
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: light?.available == true
                    ? () => openSceneEditor(context, initialSlotId: slotId)
                    : null,
                icon: const DesignIcon('scenes'),
                label: const Text('Save as a scene'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Device information'),
                children: [
                  ListTile(
                    title: Text('State: ${light?.state ?? 'Not set up'}'),
                    subtitle: Text(
                      'Colour mode: ${light?.rawAttributes['color_mode'] ?? 'Unknown'}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
