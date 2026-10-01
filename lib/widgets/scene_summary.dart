import 'package:flutter/material.dart';

import '../models/scene.dart';
import '../models/device_slot.dart';
import 'common.dart';
import 'design_assets.dart';
import 'scene_card.dart';

class SceneSummary extends StatelessWidget {
  const SceneSummary({
    required this.scene,
    required this.slots,
    this.onApply,
    this.onEdit,
    this.draft = false,
    super.key,
  });
  final LightScene scene;
  final List<DeviceSlot> slots;
  final VoidCallback? onApply, onEdit;
  final bool draft;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draft
                ? 'THE FEELING'
                : scene.isCustom
                ? 'YOUR SCENE'
                : 'PRESET',
            style: theme.textTheme.labelSmall?.copyWith(
              color: sceneAccent(scene.style),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            scene.name.isEmpty ? 'Your new scene' : scene.name,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const RoomIllustration(height: 188),
          if (scene.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(scene.description),
          ],
          const SizedBox(height: 20),
          for (final slot in slots.where(
            (slot) => scene.commands.containsKey(slot.id),
          )) ...[
            Text(slot.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              sceneLightSummary(scene.commands[slot.id]!),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
          if (scene.commands.isEmpty)
            const Text('Select a light to include it.'),
          if (draft)
            const Text(
              'Saving won’t change your lights. Scenes are saved on this device.',
            ),
          if (!draft) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onApply,
                child: const Text('Apply scene'),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onEdit,
                  child: Text(scene.isCustom ? 'Edit scene' : 'Make a copy'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
