import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../widgets/scene_card.dart';

class RoomScenesScreen extends ConsumerStatefulWidget {
  const RoomScenesScreen({super.key});

  @override
  ConsumerState<RoomScenesScreen> createState() => _RoomScenesScreenState();
}

class _RoomScenesScreenState extends ConsumerState<RoomScenesScreen> {
  late final Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = ref
        .read(appControllerProvider)
        .roomScenes
        .map((s) => s.id)
        .toSet();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(appControllerProvider.notifier)
          .setRoomScenes(_selected.toList());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenes = ref.watch(appControllerProvider.select((s) => s.scenes));
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Scenes in My room')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Text(
                      'Choose scenes for Set the mood. Hidden scenes stay available on the Scenes page.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () =>
                                      _selected.addAll(scenes.map((s) => s.id)),
                                ),
                          child: const Text('Select all'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(_selected.clear),
                          child: const Text('Clear selection'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final scene in scenes)
                          CheckboxListTile(
                            key: ValueKey('room-scene-${scene.id}'),
                            secondary: Icon(sceneIcon(scene.style)),
                            title: Text(scene.name),
                            subtitle: Text(
                              scene.isCustom ? 'Your scene' : 'Preset',
                            ),
                            value: _selected.contains(scene.id),
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      _selected.add(scene.id);
                                    } else {
                                      _selected.remove(scene.id);
                                    }
                                  }),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          key: const ValueKey('save-room-scenes'),
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save selection'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
