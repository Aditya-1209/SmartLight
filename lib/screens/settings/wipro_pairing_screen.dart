import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/pairing/tuya_pairing.dart';

class WiproPairingScreen extends StatefulWidget {
  const WiproPairingScreen({super.key, required this.lightName});
  final String lightName;
  @override
  State<WiproPairingScreen> createState() => _WiproPairingScreenState();
}

class _WiproPairingScreenState extends State<WiproPairingScreen> {
  final _pairing = TuyaPairing();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  List<PairedTuyaDevice> _devices = [];
  bool _ready = false, _busy = false, _armed = false, _blinking = false;
  String _mode = 'EZ';
  String? _error;
  String _status = '';

  @override
  void dispose() {
    unawaited(_pairing.close().catchError((Object _) {}));
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(String status, Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = status;
    });
    try {
      await operation();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Setup failed (${error.code}).',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not finish setup. Please try again.');
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

  void _use(PairedTuyaDevice device) {
    if (!device.hasLocalKey) {
      setState(
        () => _error = 'Tuya did not provide a usable local key for this light. Reopen this screen to refresh its details.',
      );
      return;
    }
    Navigator.of(context).pop(device);
  }

  Future<void> _prepare() => _run('Preparing setup…', () async {
    if (!await _pairing.available()) {
      throw PlatformException(
        code: 'not_configured',
        message:
            'Install the personal Android pairing build to use this screen.',
      );
    }
    final devices = await _pairing.prepare();
    if (mounted) {
      setState(() {
        _ready = true;
        _devices = devices;
      });
    }
  });

  Future<void> _arm() => _run('Preparing pairing…', () async {
    if (_ssid.text.isEmpty ||
        utf8.encode(_ssid.text).length > 32 ||
        utf8.encode(_password.text).length > 63) {
      throw PlatformException(
        code: 'wifi',
        message: 'Enter a valid Wi-Fi name and password.',
      );
    }
    await _pairing.prepareToken();
    if (mounted) setState(() => _armed = true);
  });

  Future<void> _pair() =>
      _run('Looking for your light. This can take two minutes…', () async {
        setState(() => _armed = false);
        final device = await _pairing.pair(
          ssid: _ssid.text,
          password: _password.text,
          mode: _mode,
        );
        if (mounted) _use(device);
      });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Pair ${widget.lightName}')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Pair inside SmartLight',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        if (!_ready) ...[
          const Text(
            'This setup uses Tuya’s service to pair a Wipro light and retrieve its local key. Internet is needed during setup. Everyday controls use your local Wi-Fi.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Continue creates a private pairing profile for this installation and sends device and connection information to Tuya. The profile is saved securely on this phone. Keep the app’s data; uninstalling or clearing it loses access to this profile.',
          ),
          const SizedBox(height: 12),
          const Text(
            'We will test one tube first. Re-pairing may remove it from Wipro Next. Compatibility with this model is still being tested. Leave your other lights as they are.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _prepare,
            child: const Text('Continue with Tuya setup'),
          ),
        ] else ...[
          if (_devices.isNotEmpty) ...[
            Text(
              'Already paired here',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final device in _devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(device.name),
                subtitle: Text(
                  device.host.isEmpty
                      ? 'Select to retrieve connection details'
                      : device.host,
                ),
                onTap: _busy ? null : () => _use(device),
              ),
            const Divider(height: 32),
          ],
          const Text(
            'Join your home Wi-Fi and enter its 2.4 GHz network details. The password is used for pairing and is not saved by SmartLight.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ssid,
            enabled: !_busy && !_armed,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Home Wi-Fi name (SSID)',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            enabled: !_busy && !_armed,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Home Wi-Fi password'),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'EZ', label: Text('Fast blinking')),
              ButtonSegment(value: 'AP', label: Text('Slow blinking / AP')),
            ],
            selected: {_mode},
            onSelectionChanged: _busy || _armed
                ? null
                : (value) => setState(() {
                    _mode = value.first;
                    _blinking = false;
                  }),
          ),
          const SizedBox(height: 16),
          Text(
            _mode == 'EZ'
                ? 'Put only this tube into its fast-blinking pairing mode using the instructions supplied with the light. Keep your phone on your home Wi-Fi.'
                : 'Put only this tube into its slow-blinking / AP pairing mode. Prepare pairing while still on your home Wi-Fi, then join the light’s Wi-Fi hotspot.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _blinking,
            onChanged: _busy
                ? null
                : (value) => setState(() => _blinking = value ?? false),
            title: Text(
              _mode == 'EZ'
                  ? 'This tube is blinking quickly'
                  : 'This tube is blinking slowly',
            ),
          ),
          if (!_armed)
            FilledButton(
              onPressed: _busy || !_blinking ? null : _arm,
              child: const Text('Prepare pairing'),
            ),
          if (_armed) ...[
            if (_mode == 'AP') ...[
              const Text(
                'Now open Wi-Fi settings, join this light’s hotspot, and return here. If Android says there is no internet, stay connected to the hotspot.',
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Opening Wi-Fi…', _pairing.wifiSettings),
                child: const Text('Open Wi-Fi settings'),
              ),
            ],
            FilledButton(
              onPressed: _busy || !_blinking ? null : _pair,
              child: const Text('Start pairing'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _armed = false),
              child: const Text('Change Wi-Fi details'),
            ),
          ],
        ],
        if (_busy) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status),
          TextButton(
            onPressed: () => _pairing.cancel(),
            child: const Text('Cancel setup'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}
