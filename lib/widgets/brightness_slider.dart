import 'package:flutter/material.dart';

class ValueSlider extends StatefulWidget {
  const ValueSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.suffix = '%',
    super.key,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double>? onChanged;
  @override
  State<ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<ValueSlider> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label)),
            Text(
              '${value.round()}${widget.suffix}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max > widget.min ? widget.max : widget.min + 1,
          divisions: widget.suffix == '%' ? 100 : null,
          label: '${value.round()}${widget.suffix}',
          semanticFormatterCallback: (v) =>
              '${widget.label}: ${v.round()}${widget.suffix}',
          onChanged: widget.onChanged == null
              ? null
              : (v) => setState(() => _drag = v),
          onChangeEnd: widget.onChanged == null
              ? null
              : (v) {
                  setState(() => _drag = null);
                  widget.onChanged!(v);
                },
        ),
      ],
    );
  }
}
