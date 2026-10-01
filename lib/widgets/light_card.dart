import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/device_slot.dart';
import '../models/light_entity.dart';
import 'brightness_slider.dart';
import 'color_picker.dart';
import 'design_assets.dart';

class LightCard extends StatelessWidget {
  const LightCard({
    required this.slot,
    required this.light,
    required this.busy,
    required this.onOpen,
    required this.onPower,
    this.onBrightness,
    super.key,
  });
  final DeviceSlot slot;
  final LightEntity? light;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onPower;
  final ValueChanged<double>? onBrightness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final on = light?.isOn == true;
    final available = light?.available == true;
    final colour =
        light?.rgbColor != null &&
        light?.rawAttributes['color_mode'] != 'color_temp';
    final accent = colour ? materialColor(light!.rgbColor!) : LightPalette.warm;
    final temperature = light?.colorTempKelvin;
    final description = light == null
        ? slot.entityId == null
              ? 'Add this light in Settings'
              : 'Waiting for light'
        : !available
        ? 'Not reachable'
        : !on
        ? 'Off'
        : colour
        ? 'Colour lighting'
        : temperature != null
        ? '${temperature < 3500
              ? 'Warm'
              : temperature > 5000
              ? 'Cool'
              : 'Soft'} white · $temperature K'
        : 'Light is on';
    return Card(
      key: ValueKey('device-${slot.id}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: DesignIcon(
                                slot.id == 'strip' ? 'strip' : 'tube',
                                color: available && on
                                    ? accent
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slot.name,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (busy)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Semantics(
                    label: '${on ? 'Turn off' : 'Turn on'} ${slot.name}',
                    child: Switch(
                      key: ValueKey('power-${slot.id}'),
                      value: on,
                      onChanged: onPower == null ? null : (_) => onPower!(),
                    ),
                  ),
              ],
            ),
            if (light?.supportsBrightness == true)
              ValueSlider(
                key: ValueKey('brightness-${slot.id}'),
                compact: true,
                label: '${slot.name} brightness',
                value: light!.brightnessPercent.toDouble(),
                color: accent,
                onChanged: busy ? null : onBrightness,
              )
            else
              SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onOpen,
                    child: Text(
                      slot.entityId == null ? 'Set up light' : 'View light',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
