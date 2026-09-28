import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/light_command.dart';
import '../../providers/app_controller.dart';
import '../../widgets/brightness_slider.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';

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
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              PageHeading(
                slot.name,
                slot.entityId ?? 'Add this light in Settings',
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatusBadge(
                            light?.available == true
                                ? 'Online · ${light!.isOn ? 'On' : 'Off'}'
                                : 'Unavailable',
                            good: light?.available == true,
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
                    if (light?.supportsBrightness == true) ...[
                      const SizedBox(height: 24),
                      ValueSlider(
                        key: const ValueKey('detail-brightness'),
                        label: 'Brightness',
                        value: light!.brightnessPercent.toDouble(),
                        onChanged: enabled
                            ? (v) => send(LightCommand(brightnessPercent: v))
                            : null,
                      ),
                    ],
                    if (light?.supportsTemperature == true) ...[
                      const SizedBox(height: 24),
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
                    ],
                    if (light?.supportsRgb == true) ...[
                      const SizedBox(height: 28),
                      Text(
                        'Color',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      LightColorPicker(
                        current: light!.rgbColor,
                        onSelected: enabled
                            ? (rgb) => send(LightCommand(rgb: rgb))
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device information',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text('State: ${light?.state ?? 'Not set up'}'),
                    Text(
                      'Color mode: ${light?.rawAttributes['color_mode'] ?? 'Unknown'}',
                    ),
                    Text(
                      'Supported modes: ${light?.supportedColorModes.join(', ') ?? 'Unknown'}',
                    ),
                    if (light?.rgbColor != null)
                      Text('RGB: ${light!.rgbColor!.toJson().join(', ')}'),
                    if (light?.colorTempKelvin != null)
                      Text('Color temperature: ${light!.colorTempKelvin} K'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
