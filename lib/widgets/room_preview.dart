import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/light_entity.dart';

@immutable
class RoomLightStyle {
  const RoomLightStyle(this.color, this.level, {this.known = true});
  static const unknown = RoomLightStyle(Colors.white, 0, known: false);
  final Color color;
  final double level;
  final bool known;

  factory RoomLightStyle.fromLight(LightEntity? light) {
    if (light == null || !light.available) return unknown;
    final rgb = light.rgbColor;
    final white =
        light.rawAttributes['color_mode'] == 'color_temp' || rgb == null;
    final color = white
        ? Color.lerp(
            const Color(0xffffa15c),
            const Color(0xffdbeaff),
            ((light.colorTempKelvin ?? 4000).clamp(2000, 6500) - 2000) / 4500,
          )!
        : Color.fromARGB(
            255,
            rgb.toJson()[0],
            rgb.toJson()[1],
            rgb.toJson()[2],
          );
    return RoomLightStyle(color, light.brightnessPercent / 100);
  }

  static RoomLightStyle lerp(RoomLightStyle a, RoomLightStyle b, double t) =>
      RoomLightStyle(
        Color.lerp(a.color, b.color, t)!,
        a.level + (b.level - a.level) * t,
        known: b.known,
      );

  @override
  bool operator ==(Object other) =>
      other is RoomLightStyle &&
      color == other.color &&
      level == other.level &&
      known == other.known;
  @override
  int get hashCode => Object.hash(color, level, known);
}

@immutable
class RoomLighting {
  const RoomLighting({
    this.tube1 = RoomLightStyle.unknown,
    this.tube2 = RoomLightStyle.unknown,
    this.strip = RoomLightStyle.unknown,
  });
  final RoomLightStyle tube1, tube2, strip;
  static RoomLighting lerp(RoomLighting a, RoomLighting b, double t) =>
      RoomLighting(
        tube1: RoomLightStyle.lerp(a.tube1, b.tube1, t),
        tube2: RoomLightStyle.lerp(a.tube2, b.tube2, t),
        strip: RoomLightStyle.lerp(a.strip, b.strip, t),
      );
  @override
  bool operator ==(Object other) =>
      other is RoomLighting &&
      tube1 == other.tube1 &&
      tube2 == other.tube2 &&
      strip == other.strip;
  @override
  int get hashCode => Object.hash(tube1, tube2, strip);
}

class _LightingTween extends Tween<RoomLighting> {
  _LightingTween({required RoomLighting end}) : super(end: end);
  @override
  RoomLighting lerp(double t) => RoomLighting.lerp(begin ?? end!, end!, t);
}

/// A private neutral base plate plus independently composited light sources.
/// No cloud image generation, asset changes or device writes occur on updates.
class RoomIllustration extends StatefulWidget {
  const RoomIllustration({
    this.height = 180,
    this.tube1,
    this.tube2,
    this.strip,
    this.imageProvider,
    super.key,
  });
  final double height;
  final LightEntity? tube1, tube2, strip;
  final ImageProvider? imageProvider;
  @override
  State<RoomIllustration> createState() => _RoomIllustrationState();
}

class _RoomIllustrationState extends State<RoomIllustration> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider? _source;
  ImageInfo? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomIllustration oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final bundled = AssetImage(
      'assets/design/room-render.png',
      bundle: DefaultAssetBundle.of(context),
    );
    ImageProvider source = widget.imageProvider ?? bundled;
    if (widget.imageProvider == null && Platform.isWindows) {
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}room-render.png',
      );
      try {
        if (file.existsSync()) source = FileImage(file);
      } on FileSystemException {
        /* Use the bundled/procedural fallback. */
      }
    }
    if (_source == source) return;
    _source = source;
    _listen(source, fallback: source == bundled ? null : bundled);
  }

  void _listen(ImageProvider source, {ImageProvider? fallback}) {
    if (_listener != null) _stream?.removeListener(_listener!);
    final stream = source.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener(
      (image, synchronous) {
        if (!mounted || !identical(_stream, stream)) return;
        void replace() {
          _image?.dispose();
          _image = image.clone();
        }

        if (synchronous) {
          replace();
        } else {
          setState(replace);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted || !identical(_stream, stream)) return;
        if (fallback != null) {
          _listen(fallback);
        } else {
          setState(() {
            _image?.dispose();
            _image = null;
          });
        }
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lighting = RoomLighting(
      tube1: RoomLightStyle.fromLight(widget.tube1),
      tube2: RoomLightStyle.fromLight(widget.tube2),
      strip: RoomLightStyle.fromLight(widget.strip),
    );
    String describe(String name, RoomLightStyle light) => !light.known
        ? '$name unavailable'
        : light.level == 0
        ? '$name off'
        : '$name ${(light.level * 100).round()} percent';
    return Semantics(
      image: true,
      label:
          'Live room preview. ${describe('Left tube', lighting.tube1)}. '
          '${describe('Right tube', lighting.tube2)}. ${describe('Side strip', lighting.strip)}.',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<RoomLighting>(
            tween: _LightingTween(end: lighting),
            duration: const Duration(milliseconds: 280),
            builder: (context, value, child) => CustomPaint(
              key: const ValueKey('live-room-preview'),
              painter: RoomLightingPainter(
                image: _image?.image,
                lighting: value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoomLightingPainter extends CustomPainter {
  const RoomLightingPainter({required this.image, required this.lighting});
  final ui.Image? image;
  final RoomLighting lighting;
  static const _bounds = Rect.fromLTWH(0, 0, 1536, 1024);
  static const leftTube = Rect.fromLTRB(226, 155, 818, 177);
  static const rightTube = Rect.fromLTRB(726, 133, 1308, 153);

  @override
  void paint(Canvas canvas, Size size) {
    final fit = applyBoxFit(BoxFit.contain, const Size(1536, 1024), size);
    final target = Alignment.center.inscribe(
      fit.destination,
      Offset.zero & size,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(target.left, target.top);
    canvas.scale(target.width / 1536, target.height / 1024);
    _base(canvas, .43);
    _spill(canvas, lighting.tube1, const Offset(500, 360), 730, 700, .55);
    _spill(canvas, lighting.tube2, const Offset(1040, 350), 730, 700, .55);
    _spill(canvas, lighting.strip, const Offset(298, 548), 170, 490, 1.05);
    _spill(canvas, lighting.strip, const Offset(1232, 548), 170, 490, 1.05);
    _emitter(canvas, leftTube, lighting.tube1, 18);
    _emitter(canvas, rightTube, lighting.tube2, 18);
    // These narrow glows are behind the two side edges, never across the desk.
    _emitter(
      canvas,
      const Rect.fromLTRB(294, 222, 301, 874),
      lighting.strip,
      30,
      concealed: true,
    );
    _emitter(
      canvas,
      const Rect.fromLTRB(1228, 222, 1235, 874),
      lighting.strip,
      30,
      concealed: true,
    );
    canvas.restore();
  }

  void _base(Canvas canvas, double factor, {Color color = Colors.white}) {
    canvas.saveLayer(
      _bounds,
      Paint()
        ..colorFilter = ColorFilter.matrix([
          color.r * factor,
          0,
          0,
          0,
          0,
          0,
          color.g * factor,
          0,
          0,
          0,
          0,
          0,
          color.b * factor,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    );
    if (image != null) {
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        _bounds,
        Paint(),
      );
    } else {
      _fallback(canvas);
    }
    canvas.restore();
  }

  void _spill(
    Canvas canvas,
    RoomLightStyle light,
    Offset center,
    double rx,
    double ry,
    double strength,
  ) {
    if (light.level <= 0 || light.color.computeLuminance() == 0) return;
    canvas.saveLayer(_bounds, Paint()..blendMode = BlendMode.plus);
    // Re-light material textures, retaining brightness across the whole range.
    _base(canvas, strength, color: light.color);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final opacity = light.level.clamp(0.0, 1.0);
    canvas.drawPaint(
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [
            Colors.white.withValues(alpha: opacity),
            Colors.white.withValues(alpha: opacity * .55),
            Colors.transparent,
          ],
          const [0, .4, 1],
        ),
    );
    canvas.restore();
    canvas.restore();
  }

  void _emitter(
    Canvas canvas,
    Rect rect,
    RoomLightStyle light,
    double blur, {
    bool concealed = false,
  }) {
    if (light.level <= 0 || light.color.computeLuminance() == 0) return;
    final alpha = math.sqrt(light.level.clamp(0, 1));
    final path = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(
      path,
      Paint()
        ..color = light.color.withValues(alpha: alpha * .65)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.drawRRect(
      path,
      Paint()
        ..color =
            (concealed
                    ? light.color
                    : Color.lerp(light.color, Colors.white, .18)!)
                .withValues(alpha: alpha * (concealed ? .4 : 1)),
    );
  }

  void _fallback(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(180, 8, 1352, 935),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xff6b6d70),
    );
    canvas.drawRect(
      const Rect.fromLTRB(298, 222, 1232, 874),
      Paint()..color = const Color(0xffd3d1c9),
    );
    canvas.drawRect(
      const Rect.fromLTRB(280, 313, 1248, 338),
      Paint()..color = const Color(0xffbdbdb6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(498, 608, 952, 867),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xff191b1d),
    );
    canvas.drawRect(
      const Rect.fromLTRB(700, 867, 744, 945),
      Paint()..color = const Color(0xff252729),
    );
    canvas.drawRect(
      const Rect.fromLTRB(112, 940, 1424, 1018),
      Paint()..color = const Color(0xffc2c1bb),
    );
    canvas.drawRect(leftTube, Paint()..color = const Color(0xff8a8b88));
    canvas.drawRect(rightTube, Paint()..color = const Color(0xff8a8b88));
  }

  @override
  bool shouldRepaint(covariant RoomLightingPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.lighting != lighting;
}
