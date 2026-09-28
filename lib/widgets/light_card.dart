import 'package:flutter/material.dart';

import '../models/device_slot.dart';
import '../models/light_entity.dart';
import 'color_picker.dart';
import 'common.dart';

class LightCard extends StatelessWidget {
  const LightCard({
    required this.slot,
    required this.light,
    required this.busy,
    required this.onOpen,
    required this.onPower,
    super.key,
  });
  final DeviceSlot slot;
  final LightEntity? light;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onPower;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = light?.isOn == true;
    final accent =
        on &&
            light?.rgbColor != null &&
            light?.rawAttributes['color_mode'] != 'color_temp'
        ? materialColor(light!.rgbColor!)
        : scheme.primary;
    return Card(
      key: ValueKey('device-${slot.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatusBadge(
                      light == null
                          ? 'Not mapped'
                          : light!.available
                          ? 'Online'
                          : 'Unavailable',
                      good: light?.available == true,
                    ),
                  ),
                  IconButton.filledTonal(
                    key: ValueKey('power-${slot.id}'),
                    tooltip: '${on ? 'Turn off' : 'Turn on'} ${slot.name}',
                    onPressed: busy ? null : onPower,
                    icon: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.power_settings_new),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: on ? .18 : .04),
                      accent.withValues(alpha: .02),
                    ],
                  ),
                ),
                child: slot.id == 'strip'
                    ? Icon(
                        Icons.waves,
                        color: on ? accent : scheme.outline,
                        size: 48,
                      )
                    : Container(
                        width: 130,
                        height: 10,
                        decoration: BoxDecoration(
                          color: on ? accent : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: on
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: .28),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ]
                              : [],
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              Text(slot.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                light == null
                    ? 'Choose an entity in Settings'
                    : !light!.available
                    ? 'Check the device in Home Assistant'
                    : '${on ? 'On' : 'Off'}${light!.supportsBrightness ? ' · ${light!.brightnessPercent}%' : ''}',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (light?.rgbColor != null) ...[
                    Icon(
                      Icons.circle,
                      color: materialColor(light!.rgbColor!),
                      size: 12,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      light?.colorTempKelvin != null
                          ? '${light!.colorTempKelvin} K'
                          : light?.rgbColor != null
                          ? 'RGB ${light!.rgbColor!.toJson().join(', ')}'
                          : 'Power control',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
