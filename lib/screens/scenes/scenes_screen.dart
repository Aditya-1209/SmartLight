import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../providers/app_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/scene_card.dart';

class ScenesScreen extends ConsumerWidget {
  const ScenesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('Scenes', 'The right light for whatever comes next.'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 600 ? 2 : 1;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: LightScene.defaults
                  .map(
                    (scene) => SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 20) / columns,
                      child: SceneCard(
                        scene: scene,
                        expanded: true,
                        onTap: state.connected && state.busy.isEmpty
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
        const SizedBox(height: 24),
        const Text(
          'Scenes adapt to each light’s supported controls. Any device that fails is reported individually.',
        ),
      ],
    );
  }
}
