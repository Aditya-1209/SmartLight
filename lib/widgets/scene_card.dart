import 'package:flutter/material.dart';

import '../models/light_command.dart';
import '../models/scene.dart';
import '../app/theme.dart';
import 'design_assets.dart';

IconData sceneIcon(String id) => switch (id) {
  'study' => Icons.wb_sunny_outlined,
  'movie' => Icons.theaters_outlined,
  'chill' => Icons.spa_outlined,
  'sleep' => Icons.bedtime_outlined,
  'music' => Icons.music_note_outlined,
  _ => Icons.auto_awesome_outlined,
};

String sceneStyleLabel(String id) => switch (id) {
  'study' => 'Sunshine',
  'movie' => 'Cinema',
  'chill' => 'Relax',
  'sleep' => 'Moonlight',
  'music' => 'Music',
  _ => 'Sparkle',
};

Color sceneAccent(String id) => switch (id) {
  'study' => LightPalette.blue,
  'movie' => LightPalette.purple,
  'chill' => LightPalette.mint,
  'sleep' => LightPalette.blue,
  'music' => const Color(0xffd989aa),
  _ => LightPalette.warm,
};

String sceneLightSummary(LightCommand command) {
  if (command.service == 'turn_off') return 'Off';
  final parts = <String>[
    if (command.brightnessPercent != null)
      '${command.brightnessPercent!.round()}%',
    if (command.rgb != null)
      'Color'
    else if (command.kelvin != null)
      command.kelvin! < 3500
          ? 'Warm white'
          : command.kelvin! > 5000
          ? 'Cool white'
          : 'Soft white',
  ];
  return parts.isEmpty ? 'On' : parts.join(' · ');
}

String sceneGlyph(String style) => switch (style) {
  'study' => 'book',
  'movie' => 'play',
  'chill' => 'scenes',
  'sleep' => 'moon',
  _ => 'sun',
};

class SceneCard extends StatelessWidget {
  const SceneCard({
    required this.scene,
    required this.onTap,
    this.expanded = false,
    this.menu,
    super.key,
  });
  final LightScene scene;
  final VoidCallback? onTap;
  final bool expanded;
  final Widget? menu;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sceneAccent(scene.style);
    final colours = switch (scene.style) {
      'study' => const [Color(0xff293a3c), Color(0xff172327)],
      'movie' => const [Color(0xff3c304c), Color(0xff221f30)],
      'chill' => const [Color(0xff23423b), Color(0xff172721)],
      'sleep' => const [Color(0xff26304a), Color(0xff171e2c)],
      _ => const [Color(0xff403125), Color(0xff211e1a)],
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('scene-${scene.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 88,
              width: double.infinity,
              child: ClipRect(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colours),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -42,
                        top: 28,
                        child: Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: .09),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -28,
                        top: 42,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: .09),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 18,
                        child: DesignIcon(
                          sceneGlyph(scene.style),
                          size: 28,
                          color: accent,
                        ),
                      ),
                      Positioned(
                        left: 54,
                        top: 62,
                        child: Container(
                          width: 88,
                          height: 2,
                          color: accent.withValues(alpha: .65),
                        ),
                      ),
                      if (menu != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconTheme(
                            data: const IconThemeData(
                              color: LightPalette.muted,
                            ),
                            child: menu!,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scene.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${scene.commands.length} lights · ${scene.isCustom ? 'Your scene' : switch (scene.style) {
                            'study' => 'Clear & bright',
                            'movie' => 'Soft & cinematic',
                            'chill' => 'Unwind',
                            'sleep' => 'Wind down',
                            _ => 'Your mood',
                          }}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
