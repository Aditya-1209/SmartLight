import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class RoomIllustration extends StatelessWidget {
  const RoomIllustration({this.height = 180, super.key});
  final double height;
  @override
  Widget build(BuildContext context) {
    const label =
        'Your desk and marble panel, with two Wipro tubes above and concealed strip lighting behind the left and right edges';
    Widget fallback() => SvgPicture.asset(
      'assets/design/room-illustration.svg',
      fit: BoxFit.contain,
      semanticsLabel:
          'A softly lit room with two wall lights and a light strip',
    );
    Widget bundled() => Image.asset(
      'assets/design/room-render.png',
      fit: BoxFit.contain,
      semanticLabel: label,
      errorBuilder: (_, error, stack) => fallback(),
    );
    // A Windows user can keep a personal render beside the app, without
    // publishing it or adding it to the shared build.
    final local = Platform.isWindows
        ? File(
            '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}room-render.png',
          )
        : null;
    return SizedBox(
      height: height,
      child: local != null && local.existsSync()
          ? Image.file(
              local,
              fit: BoxFit.contain,
              semanticLabel: label,
              errorBuilder: (_, error, stack) => bundled(),
            )
          : bundled(),
    );
  }
}
