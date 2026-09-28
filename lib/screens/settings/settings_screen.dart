import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_config.dart';
import '../../models/device_slot.dart';
import '../../models/light_entity.dart';
import '../../providers/app_controller.dart';
import '../../services/ha_exception.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final List<TextEditingController> _names;
  late List<DeviceSlot> _slots;
  List<LightEntity> _discovered = [];
  bool _working = false;
  bool _showToken = false;
  String? _message;
  bool _success = false;
  @override
  void initState() {
    super.initState();
    final state = ref.read(appControllerProvider);
    _url = TextEditingController(text: state.config?.url ?? '');
    _token = TextEditingController(text: state.config?.token ?? '');
    _slots = List.of(state.settings.slots);
    _names = _slots.map((s) => TextEditingController(text: s.name)).toList();
    if (!state.settings.demo) _discovered = state.lights.values.toList();
    _url.addListener(_invalidate);
    _token.addListener(_invalidate);
  }

  void _invalidate() {
    setState(() {
      _discovered = [];
      _message = null;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final lights = await ref
          .read(appControllerProvider.notifier)
          .inspectConnection(ConnectionConfig(_url.text, _token.text));
      if (!mounted) return;
      setState(() {
        _discovered = lights;
        _success = true;
        _message =
            'Connected. Found ${lights.length} light entities. Map your devices below.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _success = false;
          _message = userMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final slots = [
        for (var i = 0; i < _slots.length; i++)
          _slots[i].copyWith(name: _names[i].text.trim()),
      ];
      await ref
          .read(appControllerProvider.notifier)
          .saveConfiguration(ConnectionConfig(_url.text, _token.text), slots);
      if (mounted) {
        setState(() {
          _success = true;
          _message = 'Saved securely. Your room is ready.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _success = false;
          _message = userMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          state.config == null ? 'Let’s connect' : 'Settings',
          'A single connection. All your lights.',
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_outlined),
                  const SizedBox(width: 12),
                  Text(
                    'Home Assistant',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Add your lights to Home Assistant first, then create a long-lived access token in your Home Assistant profile.',
              ),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('ha-url'),
                controller: _url,
                enabled: !_working,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Home Assistant URL',
                  hintText: 'http://192.168.1.10:8123',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('ha-token'),
                controller: _token,
                enabled: !_working,
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Long-lived access token',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showToken ? 'Hide token' : 'Show token',
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(
                      _showToken
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Credentials are stored in your operating system’s secure storage. Use HTTPS when connecting outside a trusted LAN.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _working ? null : _test,
                    icon: const Icon(Icons.network_check),
                    label: const Text('Test connection'),
                  ),
                  FilledButton.icon(
                    onPressed: _working || _discovered.isEmpty ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                  if (_working)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _success
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device mapping',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a unique light for each slot. Names can be edited here anytime.',
              ),
              if (_discovered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text(
                    'Test your connection to discover available light entities.',
                  ),
                ),
              for (var i = 0; i < _slots.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _names[i],
                        enabled: !_working,
                        decoration: InputDecoration(
                          labelText:
                              '${DeviceSlot.defaults[i].name} · app name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'mapping-$i-${_slots[i].entityId}-${_discovered.length}',
                        ),
                        initialValue:
                            _discovered.any(
                              (e) => e.entityId == _slots[i].entityId,
                            )
                            ? _slots[i].entityId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Home Assistant entity',
                        ),
                        items: _discovered
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.entityId,
                                child: Text(
                                  '${e.friendlyName} · ${e.entityId}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _working || _discovered.isEmpty
                            ? null
                            : (id) => setState(
                                () => _slots[i] = _slots[i].copyWith(
                                  entityId: id,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: ThemeMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(switch (mode) {
                          ThemeMode.system => 'System',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        }),
                        selected: state.settings.theme == mode,
                        onSelected: (_) =>
                            runSetting(context, controller.setTheme(mode)),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Developer settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('demo-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Demo mode'),
                subtitle: const Text(
                  'Explore three simulated lights. Your saved Home Assistant credentials and mappings are kept.',
                ),
                value: state.settings.demo,
                onChanged: _working || state.busy.isNotEmpty
                    ? null
                    : (value) => runSetting(context, controller.setDemo(value)),
              ),
              if (state.settings.demo)
                const Text(
                  'Use Diagnostics to simulate an unavailable light or an offline server.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}
