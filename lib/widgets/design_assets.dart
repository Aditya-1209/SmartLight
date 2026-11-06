import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

export 'room_preview.dart';

/// Original vector assets used to construct the SmartLight Figma file.
class DesignIcon extends StatelessWidget {
  const DesignIcon(this.name, {this.size = 22, this.color, super.key});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/design/$name.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      BlendMode.srcIn,
    ),
  );
}
