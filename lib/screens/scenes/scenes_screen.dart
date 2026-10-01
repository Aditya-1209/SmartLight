import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../widgets/common.dart';
import '../../widgets/scene_card.dart';
import '../../widgets/scene_summary.dart';
import '../../widgets/design_assets.dart';
import 'scene_editor_screen.dart';

class ScenesScreen extends ConsumerStatefulWidget {
  const ScenesScreen({super.key});
  @override
  ConsumerState<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends ConsumerState<ScenesScreen> {
  String _filter = 'All scenes';
  String? _selectedId;

  void _edit(
    BuildContext context, {
    LightScene? scene,
    bool duplicate = false,
  }) {
    openSceneEditor(context, scene: scene, duplicate: duplicate);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LightScene scene,
  ) async {
    final controller = ref.read(appControllerProvider.notifier);
    try {
      await controller.deleteScene(scene.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“${scene.name}” deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => runSetting(context, controller.saveScene(scene)),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context);
    Widget grid(List<LightScene> scenes) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 3
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: scenes
              .map(
                (scene) => SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                  child: SceneCard(
                    scene: scene,
                    expanded: true,
                    onTap: state.connected && state.busy.isEmpty
                        ? () {
                            setState(() => _selectedId = scene.id);
                            runAction(context, controller.applyScene(scene));
                          }
                        : null,
                    menu: PopupMenuButton<String>(
                      tooltip: 'Options for ${scene.name}',
                      onSelected: (value) {
                        if (value == 'delete') {
                          _delete(context, ref, scene);
                        } else {
                          _edit(
                            context,
                            scene: scene,
                            duplicate: value == 'duplicate',
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        if (scene.isCustom)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit scene'),
                          ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate scene'),
                        ),
                        if (scene.isCustom)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete scene'),
                          ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
    final selected =
        state.scenes.where((s) => s.id == _selectedId).firstOrNull ??
        state.scenes.first;
    final collection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_filter != 'Presets') ...[
          Text('MADE BY YOU', style: theme.textTheme.labelSmall),
          const SizedBox(height: 16),
          if (state.settings.customScenes.isEmpty)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DesignIcon('scenes', size: 28),
                  const SizedBox(height: 12),
                  Text(
                    'Your room. Your routine.',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Save your favourite settings for a late-night read, a quiet morning, or anything in between.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => _edit(context),
                    child: const Text('Create a scene'),
                  ),
                ],
              ),
            )
          else
            grid(state.settings.customScenes),
          const SizedBox(height: 28),
        ],
        if (_filter != 'My scenes') ...[
          Text('Everyday favourites', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          grid(LightScene.defaults),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeading(
              wide ? 'Set the mood.' : 'Scenes',
              wide
                  ? 'Save a feeling. Come back to it in one tap.'
                  : 'One tap. A different feeling.',
              trailing: FilledButton(
                key: const ValueKey('create-scene'),
                onPressed: () => _edit(context),
                child: wide ? const Text('+ New scene') : const Icon(Icons.add),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in ['All scenes', 'My scenes', 'Presets'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == label,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = label),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: collection),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 4,
                    child: SceneSummary(
                      scene: selected,
                      slots: state.slots,
                      onApply: state.connected && state.busy.isEmpty
                          ? () => runAction(
                              context,
                              controller.applyScene(selected),
                            )
                          : null,
                      onEdit: () => _edit(
                        context,
                        scene: selected,
                        duplicate: !selected.isCustom,
                      ),
                    ),
                  ),
                ],
              )
            else
              collection,
            const SizedBox(height: 24),
            const Text(
              'Scenes are saved on this device. Only the included lights will change.',
            ),
          ],
        );
      },
    );
  }
}
