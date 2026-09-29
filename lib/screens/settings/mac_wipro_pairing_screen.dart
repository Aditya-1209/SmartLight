import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/pairing/desktop_tuya_pairing.dart';
import '../../services/pairing/tuya_cloud_setup.dart';
import '../../services/pairing/tuya_pairing.dart';

class MacWiproPairingScreen extends StatefulWidget {
  const MacWiproPairingScreen({
    super.key,
    required this.lightName,
    this.pairing,
  });
  final String lightName;
  final DesktopTuyaPairing? pairing;
  @override
  State<MacWiproPairingScreen> createState() => _MacWiproPairingScreenState();
}

class _MacWiproPairingScreenState extends State<MacWiproPairingScreen> {
  late final _pairing = widget.pairing ?? DesktopTuyaPairing();
  final _clientId = TextEditingController();
  final _secret = TextEditingController();
  final _schema = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  Map<String, String> _addresses = {};
  String? _address, _error;
  List<PairedTuyaDevice> _devices = [];
  bool _loading = true, _busy = false, _ready = false, _blinking = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final saved = await _pairing.savedConfig();
      if (!mounted) return;
      if (saved != null) {
        _clientId.text = saved.clientId;
        _secret.text = saved.secret;
        _schema.text = saved.schema;
      }
    } catch (_) {
      if (mounted) {
        _error = 'Could not load saved setup credentials from Keychain.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pairing.close();
    for (final c in [_clientId, _secret, _schema, _ssid, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String status, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = status;
    });
    try {
      await action();
    } on TuyaSetupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Setup could not finish. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _prepare() =>
      _run('Checking Tuya access before pairing…', () async {
        final devices = await _pairing.prepare(
          TuyaCloudConfig(
            clientId: _clientId.text.trim(),
            secret: _secret.text.trim(),
            schema: _schema.text.trim(),
          ),
        );
        final addresses = await _pairing.networkAddresses();
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _addresses = addresses;
          _address = addresses.isEmpty ? null : addresses.keys.first;
          _ready = true;
        });
      });
  void _use(PairedTuyaDevice device) {
    if (!device.hasLocalKey) {
      setState(
        () => _error = 'Tuya has not returned this light’s local key yet. Check setup again to refresh it.',
      );
      return;
    }
    Navigator.of(context).pop(device);
  }

  Future<void> _start() => _run(
    'Pairing from your Mac. Keep this window open (up to two minutes)…',
    () async {
      if (_ssid.text.isEmpty ||
          utf8.encode(_ssid.text).length > 32 ||
          utf8.encode(_password.text).length > 63 ||
          _address == null) {
        throw const TuyaSetupException(
          'Enter valid Wi-Fi details and select the Mac’s Wi-Fi connection.',
        );
      }
      final device = await _pairing.pair(
        ssid: _ssid.text,
        password: _password.text,
        bindAddress: _address!,
      );
      if (!mounted) return;
      _password.clear();
      _use(device);
    },
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: controller,
      enabled: !_busy && !_loading,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Pair ${widget.lightName} from Mac')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Wipro setup on this Mac',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (!_ready) ...[
              const Text(
                'Tuya is used during setup to register the light and retrieve its local key. Everyday controls then run over your home Wi-Fi. Your Mac does not need to stay on for other devices to control the light.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Use your Central Europe SmartLight cloud project, with the SmartLight SDK app linked under Devices → Link My App. These are the cloud project credentials, not your Wipro login or Android SDK keys.',
              ),
              _field(_clientId, 'Cloud Access ID'),
              _field(_secret, 'Cloud Access Secret', secret: true),
              _field(_schema, 'App schema'),
              const SizedBox(height: 16),
              const Text(
                'Check setup saves these credentials and a private pairing profile in this Mac’s Keychain, and contacts Tuya. Keep this profile to recover your paired lights. No light is reset by this step.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy || _loading ? null : _prepare,
                child: const Text('Check setup'),
              ),
            ] else ...[
              const Text(
                'Tuya setup checked. Ready to try one tube.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Already paired through this Mac'),
                for (final device in _devices)
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: Text(device.name),
                    subtitle: const Text('Use saved pairing details'),
                    onTap: _busy ? null : () => _use(device),
                  ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Keep your Mac on home Wi-Fi. Enter the network’s 2.4 GHz name and password. Choose the Mac’s Wi-Fi connection below; disconnect a VPN if it blocks local traffic.',
              ),
              _field(_ssid, 'Home Wi-Fi name (SSID)'),
              _field(_password, 'Home Wi-Fi password', secret: true),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _address,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mac Wi-Fi connection',
                ),
                items: [
                  for (final entry in _addresses.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _address = value),
              ),
              const SizedBox(height: 20),
              const Text(
                'Put only this tube into fast-blinking pairing mode, following its supplied reset instructions. Re-pairing may remove it from Wipro Next. Compatibility with this model still needs a physical test.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Your Wi-Fi details are sent locally to the light for pairing and the Wi-Fi password is not saved. Mac setup currently supports fast blinking (EZ mode).',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only this tube is blinking quickly'),
                value: _blinking,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _blinking = value ?? false),
              ),
              FilledButton(
                onPressed: _busy || !_blinking || _address == null
                    ? null
                    : _start,
                child: const Text('Pair this tube'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _pairing.cancel();
                        setState(() => _ready = false);
                      },
                child: const Text('Check setup again'),
              ),
            ],
            if (_busy || _loading) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(_loading ? 'Loading saved setup…' : _status),
              if (_busy)
                TextButton(
                  onPressed: () {
                    _pairing.cancel();
                    setState(() {
                      _ready = false;
                      _blinking = false;
                    });
                  },
                  child: const Text('Cancel setup'),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
