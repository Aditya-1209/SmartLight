import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../widgets/common.dart';
import '../../widgets/scene_card.dart';
import 'scene_editor_screen.dart';

class ScenesScreen extends ConsumerWidget {
  const ScenesScreen({super.key});

  void _edit(
    BuildContext context, {
    LightScene? scene,
    bool duplicate = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SceneEditorScreen(scene: scene, duplicate: duplicate),
      ),
    );
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
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context);
    Widget grid(List<LightScene> scenes) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 580
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
                        ? () => runAction(context, controller.applyScene(scene))
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('Scenes', 'A different mood, one tap away.'),
        Row(
          children: [
            Expanded(
              child: Text('Your scenes', style: theme.textTheme.titleLarge),
            ),
            FilledButton.icon(
              key: const ValueKey('create-scene'),
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New scene'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.settings.customScenes.isEmpty)
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your room. Your routine.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Save your favorite light settings for a late-night read, a quiet morning, or anything in between.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          grid(state.settings.customScenes),
        const SizedBox(height: 32),
        Text('Made for the moment', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Start with a favorite. Duplicate any preset to make it your own.',
        ),
        const SizedBox(height: 16),
        grid(LightScene.defaults),
        const SizedBox(height: 24),
        const Text(
          'Scenes use each light’s available controls. You’ll see a message if a light can’t be reached.',
        ),
      ],
    );
  }
}
