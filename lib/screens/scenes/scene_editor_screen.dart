import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/light_command.dart';
import '../../models/light_entity.dart';
import '../../models/scene.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../widgets/brightness_slider.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/scene_card.dart';

class SceneEditorScreen extends ConsumerStatefulWidget {
  const SceneEditorScreen({this.scene, this.duplicate = false, super.key});
  final LightScene? scene;
  final bool duplicate;
  @override
  ConsumerState<SceneEditorScreen> createState() => _SceneEditorScreenState();
}

class _SceneEditorScreenState extends ConsumerState<SceneEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description;
  late final String _id;
  late String _appearance;
  final _drafts = <String, _LightDraft>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final scene = widget.scene;
    _id = scene != null && !widget.duplicate && scene.isCustom
        ? scene.id
        : 'custom-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _name = TextEditingController(
      text: scene == null
          ? ''
          : widget.duplicate
          ? '${scene.name.substring(0, min(scene.name.length, 55))} copy'
          : scene.name,
    );
    _description = TextEditingController(text: scene?.description ?? '');
    _appearance = scene?.style ?? 'sparkle';
    final state = ref.read(appControllerProvider);
    for (final slot in state.slots) {
      final light = state.lightFor(slot);
      final command =
          scene?.commands[slot.id] ??
          (light?.available == true
              ? LightScene.capture(light!)
              : const LightCommand(brightnessPercent: 60, kelvin: 4000));
      _drafts[slot.id] = _LightDraft(
        command,
        included: scene == null || scene.commands.containsKey(slot.id),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _capture() {
    final state = ref.read(appControllerProvider);
    setState(() {
      for (final slot in state.slots) {
        final light = state.lightFor(slot);
        _drafts[slot.id] = _LightDraft(
          light?.available == true
              ? LightScene.capture(light!)
              : const LightCommand(),
          included: light?.available == true,
        );
      }
      _error = null;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Current settings captured. Save when you’re ready.'),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        _name.text.trim().isEmpty ||
        _name.text.length > 60 ||
        _description.text.length > 160) {
      setState(
        () => _error = 'Enter a scene name (up to 60 characters) and keep the description under 160 characters.',
      );
      return;
    }
    final commands = {
      for (final entry in _drafts.entries)
        if (entry.value.included) entry.key: entry.value.command,
    };
    if (commands.isEmpty) {
      setState(() => _error = 'Choose at least one light for this scene.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(appControllerProvider.notifier)
          .saveScene(
            LightScene(
              _id,
              _name.text.trim(),
              _description.text.trim(),
              commands,
              appearance: _appearance,
            ),
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).clearSnackBars();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${_name.text.trim()}” saved. Tap the scene to use it.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.scene?.isCustom == true && !widget.duplicate;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? 'Edit scene' : 'Create a scene')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const PageHeading(
                    'Make it your moment',
                    'Choose the light for your routine. Saving won’t change your room.',
                  ),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          key: const ValueKey('scene-name'),
                          controller: _name,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Scene name',
                            hintText: 'Evening unwind',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Give your scene a name.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('scene-description'),
                          controller: _description,
                          enabled: !_saving,
                          maxLength: 160,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            hintText: 'A little warmth after a long day',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Choose an icon',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final style in LightScene.appearances)
                              Tooltip(
                                message: sceneStyleLabel(style),
                                child: IconButton.filledTonal(
                                  isSelected: _appearance == style,
                                  tooltip: sceneStyleLabel(style),
                                  style: IconButton.styleFrom(
                                    backgroundColor: _appearance == style
                                        ? scheme.primaryContainer
                                        : scheme.surfaceContainerHighest,
                                    side: _appearance == style
                                        ? BorderSide(
                                            color: scheme.primary,
                                            width: 2,
                                          )
                                        : BorderSide.none,
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () =>
                                            setState(() => _appearance = style),
                                  icon: Icon(sceneIcon(style)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Build your scene',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only selected lights change. Leave a light unchecked to keep it as it is.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('capture-scene'),
                      onPressed:
                          !_saving &&
                              state.slots.any(
                                (s) => state.lightFor(s)?.available == true,
                              )
                          ? _capture
                          : null,
                      icon: const Icon(Icons.camera_outlined),
                      label: const Text('Use current light settings'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final slot in state.slots) ...[
                    _lightCard(slot.id, slot.name, state.lightFor(slot)),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('save-scene'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Saving…' : 'Save scene'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Saved on this device. Your light connections and pairing details stay the same.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lightCard(String id, String name, LightEntity? light) {
    final draft = _drafts[id]!;
    final minKelvin = light?.minColorTempKelvin.toDouble() ?? 2000;
    final maxKelvin = light?.maxColorTempKelvin.toDouble() ?? 6500;
    final supportsBrightness = light?.supportsBrightness ?? true;
    final modes = <String, String>{
      'keep': 'Keep color',
      if (light?.supportsTemperature ?? true) 'white': 'White',
      if (light?.supportsRgb ?? true) 'color': 'Color',
    };
    // Preserve a saved choice even when a currently connected replacement light
    // has different capabilities; the local transport adapts supported fields.
    if (!modes.containsKey(draft.mode)) {
      modes[draft.mode] = draft.mode == 'white' ? 'White' : 'Color';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CheckboxListTile(
              key: ValueKey('include-$id'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: draft.included,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => draft.included = value!),
              title: Text(name, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                draft.included ? 'Included in this scene' : 'Leave unchanged',
              ),
            ),
            if (draft.included) ...[
              SwitchListTile(
                key: ValueKey('scene-power-$id'),
                contentPadding: EdgeInsets.zero,
                title: Text(draft.on ? 'Turn on' : 'Turn off'),
                value: draft.on,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => draft.on = value),
              ),
              if (draft.on) ...[
                if (supportsBrightness) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Keep brightness unchanged'),
                    value: draft.brightness == null,
                    onChanged: _saving
                        ? null
                        : (keep) => setState(
                            () => draft.brightness = keep == true ? null : 60,
                          ),
                  ),
                  if (draft.brightness != null)
                    ValueSlider(
                      label: 'Brightness',
                      value: draft.brightness!,
                      min: 1,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => draft.brightness = value),
                    ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('scene-mode-$id-${draft.mode}'),
                  initialValue: draft.mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Light color'),
                  items: modes.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => draft.mode = value!),
                ),
                if (draft.mode == 'white') ...[
                  const SizedBox(height: 20),
                  ValueSlider(
                    label: 'White temperature',
                    value: draft.kelvin.toDouble(),
                    min: minKelvin,
                    max: maxKelvin,
                    suffix: ' K',
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => draft.kelvin = value.round()),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('Warm'), Text('Cool')],
                  ),
                ],
                if (draft.mode == 'color') ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.circle, color: materialColor(draft.rgb)),
                      const SizedBox(width: 8),
                      const Text('Scene color'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LightColorPicker(
                    key: ValueKey(
                      'scene-colors-$id-${draft.rgb.toJson().join('-')}',
                    ),
                    current: draft.rgb,
                    applyLabel: 'Use this color',
                    onSelected: _saving
                        ? null
                        : (rgb) => setState(() => draft.rgb = rgb),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _LightDraft {
  _LightDraft(LightCommand command, {required this.included})
    : on = command.service != 'turn_off',
      brightness = command.brightnessPercent,
      mode = command.rgb != null
          ? 'color'
          : command.kelvin != null
          ? 'white'
          : 'keep',
      rgb = command.rgb ?? const RgbColor(140, 70, 255),
      kelvin = command.kelvin ?? 4000;
  bool included, on;
  double? brightness;
  String mode;
  RgbColor rgb;
  int kelvin;
  LightCommand get command => !on
      ? const LightCommand(on: false)
      : LightCommand(
          brightnessPercent: brightness,
          rgb: mode == 'color' ? rgb : null,
          kelvin: mode == 'white' ? kelvin : null,
        );
}
