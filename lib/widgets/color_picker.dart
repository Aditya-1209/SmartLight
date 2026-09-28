import 'package:flutter/material.dart';

import '../models/light_entity.dart';

const colorPresets = <String, RgbColor>{
  'White': RgbColor(255, 255, 255),
  'Red': RgbColor(255, 0, 0),
  'Orange': RgbColor(255, 125, 0),
  'Yellow': RgbColor(255, 220, 0),
  'Green': RgbColor(0, 220, 85),
  'Cyan': RgbColor(0, 220, 255),
  'Blue': RgbColor(35, 75, 255),
  'Purple': RgbColor(140, 50, 255),
  'Pink': RgbColor(255, 70, 165),
};
Color materialColor(RgbColor value) {
  final rgb = value.toJson();
  return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
}

class LightColorPicker extends StatefulWidget {
  const LightColorPicker({
    required this.onSelected,
    this.current,
    this.custom = true,
    super.key,
  });
  final ValueChanged<RgbColor>? onSelected;
  final RgbColor? current;
  final bool custom;
  @override
  State<LightColorPicker> createState() => _LightColorPickerState();
}

class _LightColorPickerState extends State<LightColorPicker> {
  late final List<int> _rgb = (widget.current ?? const RgbColor(255, 180, 90))
      .toJson();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: colorPresets.entries
            .map(
              (entry) => Tooltip(
                message: entry.key,
                child: Semantics(
                  label: '${entry.key} color',
                  button: true,
                  enabled: widget.onSelected != null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: OutlinedButton(
                      key: ValueKey('color-${entry.key}'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: materialColor(entry.value).withValues(
                          alpha: widget.onSelected == null ? .25 : 1,
                        ),
                        shape: const CircleBorder(),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      onPressed: widget.onSelected == null
                          ? null
                          : () => widget.onSelected!(entry.value),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      if (widget.custom)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Custom color'),
          leading: const Icon(Icons.palette_outlined),
          children: [
            for (var i = 0; i < 3; i++)
              Row(
                children: [
                  SizedBox(width: 48, child: Text(['Red', 'Green', 'Blue'][i])),
                  Expanded(
                    child: Slider(
                      value: _rgb[i].toDouble(),
                      max: 255,
                      divisions: 255,
                      label: '${_rgb[i]}',
                      semanticFormatterCallback: (v) =>
                          '${['Red', 'Green', 'Blue'][i]} ${v.round()}',
                      onChanged: widget.onSelected == null
                          ? null
                          : (v) => setState(() => _rgb[i] = v.round()),
                    ),
                  ),
                  SizedBox(width: 32, child: Text('${_rgb[i]}')),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                onPressed: widget.onSelected == null
                    ? null
                    : () => widget.onSelected!(
                        RgbColor(_rgb[0], _rgb[1], _rgb[2]),
                      ),
                icon: Icon(
                  Icons.circle,
                  color: materialColor(RgbColor(_rgb[0], _rgb[1], _rgb[2])),
                ),
                label: const Text('Apply color'),
              ),
            ),
          ],
        ),
    ],
  );
}
