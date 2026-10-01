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
import '../../widgets/scene_summary.dart';
import '../../widgets/design_assets.dart';

Future<void> openSceneEditor(
  BuildContext context, {
  LightScene? scene,
  bool duplicate = false,
  String? initialSlotId,
}) async {
  final rootContext = context;
  final saved = await Navigator.of(context).push<LightScene>(
    MaterialPageRoute(
      builder: (_) => SceneEditorScreen(
        scene: scene,
        duplicate: duplicate,
        initialSlotId: initialSlotId,
      ),
    ),
  );
  if (saved == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(appControllerProvider);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .84,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '“${saved.name}” saved',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your new favourite.',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ready whenever your room needs a different feeling.',
                ),
                const SizedBox(height: 20),
                SceneSummary(
                  scene: saved,
                  slots: state.slots,
                  onApply: state.connected && state.busy.isEmpty
                      ? () async {
                          final report = await ref
                              .read(appControllerProvider.notifier)
                              .applyScene(saved);
                          if (!context.mounted) return;
                          if (!report.hasFailures) {
                            Navigator.of(sheetContext).pop();
                          }
                          if (!rootContext.mounted) return;
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(content: Text(report.message)),
                          );
                        }
                      : null,
                  onEdit: () {
                    Navigator.of(sheetContext).pop();
                    openSceneEditor(rootContext, scene: saved);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey('saved-scene-done'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class SceneEditorScreen extends ConsumerStatefulWidget {
  const SceneEditorScreen({
    this.scene,
    this.duplicate = false,
    this.initialSlotId,
    super.key,
  });
  final LightScene? scene;
  final bool duplicate;
  final String? initialSlotId;
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
  String _expandedId = 'tube1';
  String? _error;

  @override
  void initState() {
    super.initState();
    final scene = widget.scene;
    _expandedId =
        scene?.commands.keys.firstOrNull ?? widget.initialSlotId ?? 'tube1';
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
        included: scene == null
            ? widget.initialSlotId == null || widget.initialSlotId == slot.id
            : scene.commands.containsKey(slot.id),
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
      Navigator.of(context).pop(_preview);
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  LightScene get _preview =>
      LightScene(_id, _name.text.trim(), _description.text.trim(), {
        for (final e in _drafts.entries)
          if (e.value.included) e.key: e.value.command,
      }, appearance: _appearance);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final editing = widget.scene?.isCustom == true && !widget.duplicate;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: const ValueKey('scene-name'),
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 60,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Scene name',
            hintText: 'Golden hour',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Give your scene a name.'
              : null,
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          initiallyExpanded: _description.text.isNotEmpty,
          title: Text(
            'Description (optional)',
            style: theme.textTheme.bodySmall,
          ),
          children: [
            TextFormField(
              key: const ValueKey('scene-description'),
              controller: _description,
              enabled: !_saving,
              maxLength: 160,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'A warmer room. A slower evening.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Icon', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in LightScene.appearances)
              IconButton.filledTonal(
                tooltip: sceneStyleLabel(style),
                isSelected: _appearance == style,
                style: IconButton.styleFrom(
                  foregroundColor: _appearance == style
                      ? sceneAccent(style)
                      : scheme.onSurfaceVariant,
                  backgroundColor: _appearance == style
                      ? scheme.surfaceContainerHighest
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _saving
                    ? null
                    : () => setState(() => _appearance = style),
                icon: DesignIcon(
                  sceneGlyph(style),
                  color: _appearance == style
                      ? sceneAccent(style)
                      : scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('capture-scene'),
            onPressed:
                !_saving &&
                    state.slots.any((s) => state.lightFor(s)?.available == true)
                ? _capture
                : null,
            icon: const DesignIcon('scenes', size: 20),
            label: const Text('Use current lights'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Or choose a setting for each light. Uncheck a light to leave it unchanged.',
        ),
        const SizedBox(height: 20),
        for (final slot in state.slots) ...[
          _lightCard(slot.id, slot.name, state.lightFor(slot)),
          const SizedBox(height: 16),
        ],
        if (_error != null)
          Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 12),
        const Text('Saving a scene won’t change your lights.'),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? 'Edit scene' : 'New scene')),
        bottomNavigationBar: SafeArea(
          child: Container(
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
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
              ],
            ),
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.all(wide ? 40 : 20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1136),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        const PageHeading(
                          'Make it your own.',
                          'A custom scene, down to the last light.',
                        ),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: SectionCard(child: form)),
                            const SizedBox(width: 32),
                            Expanded(
                              flex: 4,
                              child: SceneSummary(
                                scene: _preview,
                                slots: state.slots,
                                draft: true,
                              ),
                            ),
                          ],
                        )
                      else
                        form,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lightCard(String id, String name, LightEntity? light) {
    final draft = _drafts[id]!;
    // An offline placeholder has no capability data. Keep the editor usable
    // offline; the transport will adapt the saved scene when a light returns.
    final capabilities = light?.available == true ? light : null;
    final minKelvin = capabilities?.minColorTempKelvin.toDouble() ?? 2000;
    final maxKelvin = capabilities?.maxColorTempKelvin.toDouble() ?? 6500;
    final supportsBrightness = capabilities?.supportsBrightness ?? true;
    final modes = <String, String>{
      'keep': 'Keep color',
      if (capabilities?.supportsTemperature ?? true) 'white': 'White',
      if (capabilities?.supportsRgb ?? true) 'color': 'Color',
    };
    // Preserve a saved choice even when a currently connected replacement light
    // has different capabilities; the local transport adapts supported fields.
    if (!modes.containsKey(draft.mode)) {
      modes[draft.mode] = draft.mode == 'white' ? 'White' : 'Color';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('include-$id'),
                  value: draft.included,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          draft.included = value!;
                          if (value) _expandedId = id;
                        }),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(
                      () => _expandedId = _expandedId == id ? '' : id,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            draft.included
                                ? sceneLightSummary(draft.command)
                                : 'Leave unchanged',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (draft.included)
                  Switch(
                    key: ValueKey('scene-power-$id'),
                    value: draft.on,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => draft.on = value),
                  ),
              ],
            ),
            if (draft.included) ...[
              if (draft.on && _expandedId == id) ...[
                if (supportsBrightness) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: const Text(
                      'Keep brightness unchanged',
                      style: TextStyle(fontSize: 12),
                    ),
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
                      color: sceneAccent('sparkle'),
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
