import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_config.dart';
import '../../services/local/tapo_discovery.dart';
import '../../services/local/tuya_lan_discovery.dart';
import '../../models/device_slot.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../services/pairing/tuya_pairing.dart';
import '../../widgets/common.dart';
import '../../widgets/design_assets.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'wipro_pairing_screen.dart';
import 'mac_wipro_pairing_screen.dart';
import 'setup_transfer_screen.dart';

final tapoDiscoveryProvider = Provider<TapoDiscover>(
  (ref) => TapoDiscovery.discover,
);

final tuyaDiscoveryProvider = Provider<TuyaDiscover>(
  (ref) => TuyaLanDiscovery.scan,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context);
    Widget row(
      String icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DesignIcon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('Settings', 'Make SmartLight feel like yours.'),
        Text('YOUR SETUP', style: theme.textTheme.labelSmall),
        const SizedBox(height: 12),
        row(
          'bulb',
          'Connected lights',
          '${state.config?.devices.length ?? 0} saved connections',
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ConnectedLightsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        row(
          'transfer',
          'Transfer setup',
          'Move light connections to another device',
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SetupTransferScreen()),
          ),
        ),
        const SizedBox(height: 28),
        Text('PREFERENCES', style: theme.textTheme.labelSmall),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const DesignIcon('moon'),
                  const SizedBox(width: 12),
                  Text('Appearance', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }),
                      selected: state.settings.theme == mode,
                      onSelected: (_) =>
                          runSetting(context, controller.setTheme(mode)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        row(
          'wifi',
          'Connection diagnostics',
          'Check a light that isn’t responding',
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Connection diagnostics')),
                body: const SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: DiagnosticsScreen(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesignIcon('shield', size: 26),
              SizedBox(height: 12),
              Text(
                'Your room, your control.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Control your lights while you’re on the same Wi-Fi. Your connections are stored securely on this device.',
              ),
              SizedBox(height: 8),
              Text('Custom scenes are saved on this device.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: SwitchListTile(
            key: const ValueKey('demo-toggle'),
            title: const Text('Demo mode'),
            subtitle: const Text(
              'Explore simulated lights. Your saved connections are kept.',
            ),
            value: state.settings.demo,
            onChanged: state.busy.isNotEmpty
                ? null
                : (v) => runSetting(context, controller.setDemo(v)),
          ),
        ),
        const SizedBox(height: 16),
        const AboutListTile(
          applicationName: 'SmartLight',
          applicationVersion: '2.6.1',
          icon: Icon(Icons.info_outline),
        ),
      ],
    );
  }
}

class ConnectedLightsScreen extends ConsumerWidget {
  const ConnectedLightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Connected lights')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeading(
                  'Your lights',
                  'Keep your lights powered and join the same Wi-Fi.',
                ),
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
              ],
            ),
          ),
        ),
      ),
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
  bool _autoProtocol = true;
  String? _message;
  String _macAddress = '';

  Future<void> _findTapo() async {
    setState(() {
      _working = true;
      _message = 'Looking for Tapo lights on your Wi-Fi…';
      _success = false;
    });
    try {
      final lights = await ref.read(tapoDiscoveryProvider)();
      if (!mounted) return;
      if (lights.isEmpty) {
        setState(
          () => _message = 'No Tapo lights found. Keep the strip powered and join the same Wi-Fi, then try again.',
        );
        return;
      }
      final selected = await showDialog<TapoDiscoveredLight>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose your Tapo light'),
          children: [
            for (final light in lights)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, light),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(light.model),
                      Text(
                        '${light.host} · ${light.macAddress}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _host.text = selected.host;
        _macAddress = selected.macAddress;
        _message = 'Light found. Choose Connect & save to verify it and remember it when its address changes.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not search this network. Join your home Wi-Fi and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _findTube() async {
    if (_id.text.trim().isEmpty) {
      setState(
        () => _message = 'Select your already paired tube first so its Device ID is filled in.',
      );
      return;
    }
    final id = _id.text.trim();
    setState(() {
      _working = true;
      _message = 'Finding this tube on your Wi-Fi…';
    });
    try {
      final found = await ref.read(tuyaDiscoveryProvider)();
      if (!mounted || _id.text.trim() != id) return;
      final hosts = found
          .where(
            (d) => d.deviceId == id && DeviceConnection.isLocalAddress(d.host),
          )
          .map((d) => d.host)
          .toSet();
      setState(() {
        _success = false;
        if (hosts.length == 1) {
          _host.text = hosts.single;
          _message = 'Tube found. Choose Connect & save to verify its existing key and save the new address.';
        } else {
          _message = 'Could not identify this tube on the network. Keep its wall switch on, wait for Wi-Fi to reconnect and try again. No factory reset is needed for an IP change.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not search this network. Join your home Wi-Fi and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

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
      _autoProtocol = true;
      if (device.profile != null) _profile = device.profile!;
      _success = true;
      _message =
          'Pairing details received. '
          '${device.host.isEmpty ? 'Enter the light’s local IP address. ' : ''}'
          'The local protocol will be detected when you test the connection. '
          'Use Connect & save to verify local control and save the connection.';
    });
  }

  @override
  void initState() {
    super.initState();
    final d = widget.saved;
    _macAddress = d?.macAddress ?? '';
    _brand =
        d?.brand ??
        (widget.slot.id == 'strip' ? DeviceBrand.tapo : DeviceBrand.tuya);
    _version = d?.version ?? TuyaVersion.v33;
    _autoProtocol = d == null;
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
    if (_sameDeviceSettings(widget.saved, _localSave)) {
      _host.text = widget.saved!.host;
      _macAddress = widget.saved!.macAddress;
      _localSave = null;
      return;
    }
    final d = widget.saved;
    final old = oldWidget.saved;
    if (d != null && old != null && _sameDeviceSettings(d, old)) {
      // Background reconnection must not replace unfinished edits in this form.
      if (_host.text == old.host) _host.text = d.host;
      if (_macAddress == old.macAddress) _macAddress = d.macAddress;
      return;
    }
    _macAddress = d?.macAddress ?? '';
    _brand =
        d?.brand ??
        (widget.slot.id == 'strip' ? DeviceBrand.tapo : DeviceBrand.tuya);
    _version = d?.version ?? TuyaVersion.v33;
    _autoProtocol = d == null;
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

  bool _sameDeviceSettings(DeviceConnection? a, DeviceConnection? b) =>
      a != null &&
      b != null &&
      a.slotId == b.slotId &&
      a.name == b.name &&
      a.brand == b.brand &&
      a.email == b.email &&
      a.password == b.password &&
      a.deviceId == b.deviceId &&
      a.localKey == b.localKey &&
      a.version == b.version &&
      a.profile == b.profile &&
      a.minKelvin == b.minKelvin &&
      a.maxKelvin == b.maxKelvin;

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
    macAddress: _brand == DeviceBrand.tapo ? _macAddress : '',
  );
  Future<void> _connect(bool save) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      var config = _config();
      final controller = ref.read(appControllerProvider.notifier);
      final detect = config.brand == DeviceBrand.tuya && _autoProtocol;
      if (detect) {
        config = await controller.detectTuyaProtocol(
          config,
          stillWanted: () => mounted,
          onTrying: (version) {
            if (mounted) {
              setState(() {
                _success = false;
                _message =
                    'Checking Tuya ${DeviceConnection.versionText(version)}…';
              });
            }
          },
        );
        if (!mounted) return;
        setState(() {
          _version = config.version;
          _autoProtocol = false;
        });
      }
      if (save) {
        _localSave = config;
        await controller.saveDevice(config);
      } else if (!detect) {
        final light = await controller.inspectDevice(config);
        if (mounted) {
          setState(() {
            _host.text =
                light.rawAttributes['connection_host'] as String? ??
                config.host;
            _macAddress =
                DeviceConnection.normalizeMac(
                  light.rawAttributes['device_mac'],
                ) ??
                config.macAddress;
          });
        }
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
          OutlinedButton.icon(
            onPressed: _working ? null : _findTapo,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Find Tapo light'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _macAddress.isEmpty
                  ? 'Find and save your strip once to reconnect automatically when its IP changes.'
                  : widget.saved?.macAddress == _macAddress
                  ? 'SmartLight remembers this light and finds its new address automatically.'
                  : 'Connect & save to remember this light when its address changes.',
            ),
          ),
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
          OutlinedButton.icon(
            onPressed: _working ? null : _findTube,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Find this tube'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Saved tubes reconnect automatically when their IP changes. Keep the wall switch on while reconnecting; an IP change does not require a factory reset.',
            ),
          ),
          _field(_key, 'Local key (16 bytes)', 'local-key', secret: true),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(
              'protocol-${widget.slot.id}-${_autoProtocol ? 'auto' : _version.name}',
            ),
            initialValue: _autoProtocol ? 'auto' : _version.name,
            decoration: const InputDecoration(
              labelText: 'Local protocol version',
            ),
            items: [
              const DropdownMenuItem(
                value: 'auto',
                child: Text('Auto — test 3.3, 3.4 and 3.5'),
              ),
              ...TuyaVersion.values.map(
                (v) => DropdownMenuItem(
                  value: v.name,
                  child: Text(DeviceConnection.versionText(v)),
                ),
              ),
            ],
            onChanged: _working
                ? null
                : (v) => setState(() {
                    _autoProtocol = v == 'auto';
                    if (!_autoProtocol) {
                      _version = TuyaVersion.values.byName(v!);
                    }
                    _message = null;
                  }),
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
