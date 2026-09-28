import 'package:flutter/material.dart';

import '../models/scene.dart';

IconData sceneIcon(String id) => switch (id) {
  'study' => Icons.menu_book_outlined,
  'movie' => Icons.theaters_outlined,
  'chill' => Icons.spa_outlined,
  _ => Icons.bedtime_outlined,
};

class SceneCard extends StatelessWidget {
  const SceneCard({
    required this.scene,
    required this.onTap,
    this.expanded = false,
    super.key,
  });
  final LightScene scene;
  final VoidCallback? onTap;
  final bool expanded;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('scene-${scene.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              sceneIcon(scene.id),
              size: 28,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(scene.name, style: Theme.of(context).textTheme.titleMedium),
            if (expanded) ...[
              const SizedBox(height: 8),
              Text(scene.description),
              const SizedBox(height: 16),
              Text(switch (scene.id) {
                'study' => 'Tubes 100% · Strip 60%\nNeutral white',
                'movie' => 'Tubes off · Strip 15%\nPurple blue',
                'chill' => 'Tubes 30% · Strip 25%\nWarm white & purple',
                _ => 'Tubes off · Strip 5%\nA soft red glow',
              }),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Activate scene',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
