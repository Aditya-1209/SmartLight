import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_config.dart';
import '../../models/device_slot.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../services/pairing/tuya_pairing.dart';
import '../../widgets/common.dart';
import 'wipro_pairing_screen.dart';
import 'mac_wipro_pairing_screen.dart';
import 'setup_transfer_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Settings',
          'Your lights. Your Wi-Fi. Ready when you are.',
        ),
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect directly',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                'Keep the lights powered and join the same Wi-Fi. Add one light at a time; the rest can wait. Only the device running SmartLight needs to be on.',
              ),
              SizedBox(height: 10),
              Text(
                'Find each light’s IP address in its original app or your router’s connected devices. Reserve that address in your router so it stays the same.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final slot in DeviceSlot.defaults) ...[
          DeviceSetupCard(
            key: ValueKey('setup-${slot.id}'),
            slot: slot,
            saved: state.config?.devices
                .where((d) => d.slotId == slot.id)
                .firstOrNull,
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices),
            title: const Text('Use lights on another device'),
            subtitle: const Text(
              'Pair once, then transfer setup to Mac, Android or Windows.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SetupTransferScreen()),
            ),
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
        const AboutListTile(
          applicationName: 'SmartLight',
          applicationVersion: '2.3.0',
          icon: Icon(Icons.info_outline),
        ),
        SectionCard(
          child: SwitchListTile(
            key: const ValueKey('demo-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Demo mode'),
            subtitle: const Text(
              'Explore three simulated lights. Your saved device connections are kept.',
            ),
            value: state.settings.demo,
            onChanged: state.busy.isNotEmpty
                ? null
                : (v) => runSetting(context, controller.setDemo(v)),
          ),
        ),
      ],
    );
  }
}

class DeviceSetupCard extends ConsumerStatefulWidget {
  const DeviceSetupCard({super.key, required this.slot, this.saved});
  final DeviceSlot slot;
  final DeviceConnection? saved;
  @override
  ConsumerState<DeviceSetupCard> createState() => _DeviceSetupCardState();
}

class _DeviceSetupCardState extends ConsumerState<DeviceSetupCard> {
  DeviceConnection? _localSave;
  late final TextEditingController _name,
      _host,
      _email,
      _password,
      _id,
      _key,
      _min,
      _max;
  late DeviceBrand _brand;
  TuyaVersion _version = TuyaVersion.v33;
  TuyaProfile _profile = TuyaProfile.modern;
  bool _working = false, _reveal = false, _success = false;
  String? _message;

  Future<void> _pairWipro() async {
    final device = await Navigator.of(context).push<PairedTuyaDevice>(
      MaterialPageRoute(
        builder: (_) => Platform.isMacOS
            ? MacWiproPairingScreen(lightName: _name.text)
            : WiproPairingScreen(lightName: _name.text),
      ),
    );
    if (!mounted || device == null) return;
    setState(() {
      _id.text = device.deviceId;
      _key.text = device.localKey;
      _host.text = device.host;
      if (device.version != null) _version = device.version!;
      if (device.profile != null) _profile = device.profile!;
      _success = true;
      _message =
          'Pairing details received. '
          '${device.host.isEmpty ? 'Enter the light’s local IP address. ' : ''}'
          '${device.version == null ? 'Check the local protocol version. ' : ''}'
          'Use Connect & save to verify local control and save the connection.';
    });
  }

  @override
  void initState() {
    super.initState();
    final d = widget.saved;
    _brand =
        d?.brand ??
        (widget.slot.id == 'strip' ? DeviceBrand.tapo : DeviceBrand.tuya);
    _version = d?.version ?? TuyaVersion.v33;
    _profile = d?.profile ?? TuyaProfile.modern;
    _name = TextEditingController(text: d?.name ?? widget.slot.name);
    _host = TextEditingController(
      text:
          d?.host ??
          (widget.slot.id == 'strip'
              ? const String.fromEnvironment('SMARTLIGHT_TAPO_IP')
              : ''),
    );
    _email = TextEditingController(text: d?.email ?? '');
    _password = TextEditingController(text: d?.password ?? '');
    _id = TextEditingController(text: d?.deviceId ?? '');
    _key = TextEditingController(text: d?.localKey ?? '');
    _min = TextEditingController(text: '${d?.minKelvin ?? 2700}');
    _max = TextEditingController(text: '${d?.maxKelvin ?? 6500}');
  }

  @override
  void didUpdateWidget(covariant DeviceSetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.saved, oldWidget.saved)) return;
    // A save from this form already has the right fields and success feedback.
    // Imports, by contrast, must replace the old form and clear its status.
    if (_localSave != null && identical(widget.saved, _localSave)) {
      _localSave = null;
      return;
    }
    final d = widget.saved;
    _brand =
        d?.brand ??
        (widget.slot.id == 'strip' ? DeviceBrand.tapo : DeviceBrand.tuya);
    _version = d?.version ?? TuyaVersion.v33;
    _profile = d?.profile ?? TuyaProfile.modern;
    _name.text = d?.name ?? widget.slot.name;
    _host.text = d?.host ?? '';
    _email.text = d?.email ?? '';
    _password.text = d?.password ?? '';
    _id.text = d?.deviceId ?? '';
    _key.text = d?.localKey ?? '';
    _min.text = '${d?.minKelvin ?? 2700}';
    _max.text = '${d?.maxKelvin ?? 6500}';
    _message = null;
    _success = false;
    _reveal = false;
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _email, _password, _id, _key, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  DeviceConnection _config() => DeviceConnection(
    slotId: widget.slot.id,
    name: _name.text.trim(),
    brand: _brand,
    host: _host.text,
    email: _email.text.trim(),
    password: _password.text,
    deviceId: _id.text.trim(),
    localKey: _key.text,
    version: _version,
    profile: _profile,
    minKelvin: int.tryParse(_min.text) ?? 0,
    maxKelvin: int.tryParse(_max.text) ?? 0,
  );
  Future<void> _connect(bool save) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final config = _config();
      final controller = ref.read(appControllerProvider.notifier);
      if (save) {
        _localSave = config;
        await controller.saveDevice(config);
      } else {
        await controller.inspectDevice(config);
      }
      if (mounted) {
        setState(() {
          _success = true;
          _message = save
              ? 'Connected and saved securely.'
              : 'Connected. This light is ready to save.';
        });
      }
    } catch (error) {
      _localSave = null;
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

  Widget _field(
    TextEditingController c,
    String label,
    String key, {
    String? hint,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      key: ValueKey('${widget.slot.id}-$key'),
      enabled: !_working,
      obscureText: secret && !_reveal,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: keyboard,
      onChanged: (_) {
        if (_message != null) setState(() => _message = null);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: secret
            ? IconButton(
                tooltip: _reveal ? 'Hide credential' : 'Show credential',
                onPressed: () => setState(() => _reveal = !_reveal),
                icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
              )
            : null,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => SectionCard(
    child: ExpansionTile(
      key: ValueKey('expand-${widget.slot.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 18),
      initiallyExpanded: widget.slot.id == 'strip' && widget.saved == null,
      leading: Icon(
        widget.slot.id == 'strip'
            ? Icons.light_outlined
            : Icons.lightbulb_outline,
      ),
      title: Text(widget.saved?.name ?? widget.slot.name),
      subtitle: Text(
        widget.saved == null
            ? 'Not connected · tap to set up'
            : '${widget.saved!.host} · ${widget.saved!.protocolLabel}',
      ),
      children: [
        _field(_name, 'Name in your room', 'name'),
        DropdownButtonFormField<DeviceBrand>(
          isExpanded: true,
          initialValue: _brand,
          decoration: const InputDecoration(labelText: 'Light type'),
          items: const [
            DropdownMenuItem(
              value: DeviceBrand.tuya,
              child: Text('Wipro / Tuya Wi-Fi light'),
            ),
            DropdownMenuItem(
              value: DeviceBrand.tapo,
              child: Text('Tapo light'),
            ),
          ],
          onChanged: _working
              ? null
              : (v) => setState(() {
                  _brand = v!;
                  _message = null;
                }),
        ),
        const SizedBox(height: 14),
        _field(
          _host,
          'Light IP address',
          'host',
          hint: '192.168.1.50',
          keyboard: TextInputType.number,
        ),
        if (_brand == DeviceBrand.tapo) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Use the account that owns this light in Tapo. Enable Third-Party Compatibility in Tapo if available. Your credentials stay on this device.',
            ),
          ),
          _field(
            _email,
            'Tapo email',
            'email',
            keyboard: TextInputType.emailAddress,
          ),
          _field(_password, 'Tapo password', 'password', secret: true),
        ] else ...[
          if (Platform.isAndroid || Platform.isMacOS) ...[
            OutlinedButton.icon(
              onPressed: _working ? null : _pairWipro,
              icon: const Icon(Icons.add_link),
              label: const Text('Pair inside SmartLight'),
            ),
            const SizedBox(height: 14),
          ],
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'A Wipro password cannot unlock local control. You need this light’s device ID and local key from a compatible Tuya account or an existing key export. Compatibility with SB22240 must be tested.',
            ),
          ),
          _field(_id, 'Device ID', 'device-id'),
          _field(_key, 'Local key (16 bytes)', 'local-key', secret: true),
          DropdownButtonFormField<TuyaVersion>(
            isExpanded: true,
            key: ValueKey('protocol-${widget.slot.id}-${_version.name}'),
            initialValue: _version,
            decoration: const InputDecoration(
              labelText: 'Local protocol version',
            ),
            items: TuyaVersion.values
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(DeviceConnection.versionText(v)),
                  ),
                )
                .toList(),
            onChanged: _working ? null : (v) => setState(() => _version = v!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<TuyaProfile>(
            key: ValueKey('profile-${widget.slot.id}-${_profile.name}'),
            initialValue: _profile,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Light profile'),
            items: const [
              DropdownMenuItem(
                value: TuyaProfile.modern,
                child: Text('Modern RGB + white (DP 20–24)'),
              ),
              DropdownMenuItem(
                value: TuyaProfile.legacy,
                child: Text('Legacy RGB + white (DP 1–5)'),
              ),
            ],
            onChanged: _working ? null : (v) => setState(() => _profile = v!),
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Local key and white range help'),
            children: [
              const Text(
                'If your light is supported in Smart Life or Tuya Smart, a one-time Tuya developer account link and TinyTuya wizard can export its ID and local key. Wipro Next accounts are not guaranteed to link. Do not reset all your lights to try this. See LOCAL_SETUP.md in the project for the steps and limitations. Never share your local keys or password in chat.',
              ),
              const SizedBox(height: 12),
              _field(
                _min,
                'Warmest white (K)',
                'min-kelvin',
                keyboard: TextInputType.number,
              ),
              _field(
                _max,
                'Coolest white (K)',
                'max-kelvin',
                keyboard: TextInputType.number,
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _message!,
              style: TextStyle(
                color: _success
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: _working ? null : () => _connect(false),
              child: const Text('Test connection'),
            ),
            FilledButton.icon(
              key: ValueKey('save-${widget.slot.id}'),
              onPressed: _working ? null : () => _connect(true),
              icon: _working
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Connect & save'),
            ),
            if (widget.saved != null)
              TextButton(
                onPressed: _working
                    ? null
                    : () async {
                        setState(() => _working = true);
                        try {
                          await ref
                              .read(appControllerProvider.notifier)
                              .removeDevice(widget.slot.id);
                          if (mounted) {
                            setState(() {
                              _password.clear();
                              _key.clear();
                              _message = 'Device removed from SmartLight.';
                              _success = true;
                            });
                          }
                        } catch (error) {
                          if (mounted) {
                            setState(() {
                              _message = userMessage(error);
                              _success = false;
                            });
                          }
                        } finally {
                          if (mounted) setState(() => _working = false);
                        }
                      },
                child: const Text('Remove connection'),
              ),
          ],
        ),
      ],
    ),
  );
}
