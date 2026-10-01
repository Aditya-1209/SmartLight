import 'package:flutter/material.dart';

import '../models/light_command.dart';
import '../models/scene.dart';
import 'color_picker.dart';

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
  'study' => const Color(0xffd39a4a),
  'movie' => const Color(0xff9b86dd),
  'chill' => const Color(0xff6eb89b),
  'sleep' => const Color(0xff7a9fd8),
  'music' => const Color(0xffd989aa),
  _ => const Color(0xff60b9bf),
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
    final theme = Theme.of(context), accent = sceneAccent(scene.style);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('scene-${scene.id}'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .13),
                accent.withValues(alpha: .015),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(expanded ? 24 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        sceneIcon(scene.style),
                        size: 23,
                        color: theme.brightness == Brightness.dark
                            ? accent
                            : Color.lerp(accent, Colors.black, .35),
                      ),
                    ),
                    const Spacer(),
                    if (menu != null)
                      menu!
                    else
                      Icon(
                        Icons.north_east,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  scene.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  expanded && scene.description.isNotEmpty
                      ? scene.description
                      : '${scene.commands.length} ${scene.commands.length == 1 ? 'light' : 'lights'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (expanded) ...[
                  const SizedBox(height: 20),
                  for (final entry in scene.commands.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: entry.value.service == 'turn_off'
                                ? theme.colorScheme.outline
                                : entry.value.rgb != null
                                ? materialColor(entry.value.rgb!)
                                : accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${switch (entry.key) {
                                'tube1' => 'Tube 1',
                                'tube2' => 'Tube 2',
                                _ => 'Strip',
                              }}  ·  ${sceneLightSummary(entry.value)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: onTap == null
                            ? theme.disabledColor
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Activate scene',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: onTap == null
                              ? theme.disabledColor
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
