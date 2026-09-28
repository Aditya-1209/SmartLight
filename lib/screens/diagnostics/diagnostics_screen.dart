import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../providers/app_controller.dart';
import '../../widgets/common.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Diagnostics',
          'A clear view of your connection and devices.',
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connection', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              SelectableText(
                'Home Assistant: ${state.settings.demo ? 'Demo backend' : state.config?.url ?? 'Not configured'}',
              ),
              Text(
                'REST: ${state.connected ? 'Connected' : 'Offline / not connected'}',
              ),
              Text('WebSocket: ${state.realtime.name}'),
              Text(
                'Last successful refresh: ${state.lastRefresh?.toLocal().toString().split('.').first ?? 'Never'}',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: state.loading || !state.configured
                    ? null
                    : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh states'),
              ),
              if (state.settings.demo)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Simulate server offline'),
                  value: !state.connected,
                  onChanged: state.loading
                      ? null
                      : (v) =>
                            runSetting(context, controller.setDemoOffline(v)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final slot in state.slots) ...[
          SectionCard(
            child: Builder(
              builder: (context) {
                final light = state.lightFor(slot);
                final enabled =
                    light?.available == true &&
                    state.connected &&
                    state.busy.isEmpty;
                void send(LightCommand command) =>
                    runAction(context, controller.control(slot, command));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SelectableText('Entity: ${slot.entityId ?? 'Not mapped'}'),
                    Text('Available: ${light?.available ?? false}'),
                    Text('Power: ${light?.state ?? 'Unknown'}'),
                    Text(
                      'Brightness: ${light?.brightness ?? '—'} / 255 (${light?.brightnessPercent ?? 0}%)',
                    ),
                    Text('RGB: ${light?.rgbColor?.toJson().join(', ') ?? '—'}'),
                    Text('Temperature: ${light?.colorTempKelvin ?? '—'} K'),
                    Text(
                      'Supported modes: ${light?.supportedColorModes.join(', ') ?? '—'}',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: enabled
                              ? () => send(LightCommand(on: !light!.isOn))
                              : null,
                          child: const Text('Test power'),
                        ),
                        OutlinedButton(
                          onPressed: enabled && light!.supportsBrightness
                              ? () => send(
                                  const LightCommand(brightnessPercent: 50),
                                )
                              : null,
                          child: const Text('Test brightness'),
                        ),
                        OutlinedButton(
                          onPressed: enabled && light!.supportsRgb
                              ? () => send(
                                  const LightCommand(rgb: RgbColor(255, 0, 0)),
                                )
                              : null,
                          child: const Text('Test red'),
                        ),
                        OutlinedButton(
                          onPressed:
                              enabled &&
                                  (light!.supportsTemperature ||
                                      light.supportsRgb)
                              ? () => send(
                                  light.supportsTemperature
                                      ? const LightCommand(kelvin: 4000)
                                      : const LightCommand(
                                          rgb: RgbColor(255, 255, 255),
                                        ),
                                )
                              : null,
                          child: const Text('Test white'),
                        ),
                      ],
                    ),
                    if (state.settings.demo)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Device available'),
                        value: light?.available ?? false,
                        onChanged: (v) =>
                            controller.setDemoAvailability(slot, v),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
