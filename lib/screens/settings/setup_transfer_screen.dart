import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_config.dart';
import '../../providers/app_controller.dart';
import '../../services/device_exception.dart';
import '../../services/setup_transfer.dart';

final setupTransferProvider = Provider<SetupTransfer>(
  (ref) => const SetupTransfer(),
);

class SetupTransferScreen extends ConsumerStatefulWidget {
  const SetupTransferScreen({super.key});
  @override
  ConsumerState<SetupTransferScreen> createState() =>
      _SetupTransferScreenState();
}

class _SetupTransferScreenState extends ConsumerState<SetupTransferScreen> {
  final _password = TextEditingController(), _code = TextEditingController();
  bool _sending = true, _busy = false;
  String? _error, _message, _exported;
  ConnectionConfig? _incoming;
  final _selected = <String>{};

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
    _incoming = null;
    _exported = null;
    _selected.clear();
    _message = null;
    _error = null;
  });

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await operation();
    } on SetupTransferException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    final config = await ref
        .read(appControllerProvider.notifier)
        .configurationForTransfer();
    final code = await ref
        .read(setupTransferProvider)
        .seal(config, _password.text);
    if (mounted) setState(() => _exported = code);
  });

  Future<void> _unlock() => _run(() async {
    final config = await ref
        .read(setupTransferProvider)
        .open(_code.text, _password.text);
    if (!mounted) return;
    setState(() {
      _incoming = config;
      _selected.addAll(config.devices.map((d) => d.slotId));
    });
  });

  Future<void> _save() => _run(() async {
    final config = ConnectionConfig(
      _incoming!.devices.where((d) => _selected.contains(d.slotId)).toList(),
    );
    await ref.read(appControllerProvider.notifier).importConnections(config);
    if (!mounted) return;
    _password.clear();
    _code.clear();
    setState(() {
      _incoming = null;
      _selected.clear();
      _message = 'Connections saved securely. Open My Room to check which lights are reachable.';
    });
  });

  @override
  Widget build(BuildContext context) {
    final existing =
        ref.watch(appControllerProvider).config?.devices ??
        <DeviceConnection>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Use lights on another device')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Pair each light once. Transfer its saved connection to SmartLight on Mac, Android or Windows, then use any of them on the same home Wi-Fi. No device needs to stay on for the others.',
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Send setup')),
                  ButtonSegment(value: false, label: Text('Receive setup')),
                ],
                selected: {_sending},
                onSelectionChanged: _busy
                    ? null
                    : (v) {
                        _password.clear();
                        _code.clear();
                        _invalidate();
                        setState(() => _sending = v.first);
                      },
              ),
              const SizedBox(height: 20),
              if (_sending) ...[
                const Text(
                  'This code includes the device addresses and login credentials for the saved lights listed below, including Tapo credentials if configured. Protect it with a new transfer password. Share that password separately with your other device.',
                ),
                if (existing.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No saved lights yet. Pair one light and use Connect & save first.',
                    ),
                  ),
                for (final device in existing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(device.name),
                    subtitle: Text(device.host),
                  ),
              ] else ...[
                const Text(
                  'Paste the encrypted code created on your other device and enter its transfer password. You can review the lights before saving.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('transfer-code'),
                  controller: _code,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: SetupTransfer.maxCodeLength,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => _invalidate(),
                  decoration: const InputDecoration(labelText: 'Setup code'),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('transfer-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => _invalidate(),
                decoration: const InputDecoration(
                  labelText: 'Transfer password',
                  helperText: 'At least 12 characters. Use the same password on both devices.',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed:
                    _busy ||
                        !SetupTransfer.validPassword(_password.text) ||
                        (_sending
                            ? existing.isEmpty
                            : _code.text.trim().isEmpty)
                    ? null
                    : _sending
                    ? _create
                    : _unlock,
                child: Text(
                  _sending ? 'Create encrypted code' : 'Unlock and review',
                ),
              ),
              if (_exported != null) ...[
                const SizedBox(height: 20),
                const Text(
                  'Copy this code to your other device. There, open Settings → Use lights on another device → Receive setup. No Tuya developer credentials or Wi-Fi password are included.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await Clipboard.setData(
                            ClipboardData(text: _exported!),
                          );
                          if (mounted) {
                            setState(
                              () => _message = 'Encrypted setup code copied.',
                            );
                          }
                        }),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy encrypted code'),
                ),
              ],
              if (_incoming != null) ...[
                const SizedBox(height: 20),
                const Text(
                  'Choose connections to save. Selected room slots replace their existing connection; other saved lights are kept.',
                ),
                for (final device in _incoming!.devices)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(device.slotId),
                    onChanged: _busy
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(device.slotId);
                            } else {
                              _selected.remove(device.slotId);
                            }
                          }),
                    title: Text(device.name),
                    subtitle: Text(
                      '${device.host}${existing.any((d) => d.slotId == device.slotId) ? ' · Replaces saved connection' : ''}',
                    ),
                  ),
                FilledButton(
                  onPressed: _busy || _selected.isEmpty ? null : _save,
                  child: const Text('Save selected lights'),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
