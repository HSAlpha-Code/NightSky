import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models.dart';
import '../state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _controller = TextEditingController(text: ref.read(serverUrlProvider));
  String? _status;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final url = _controller.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _status = 'Enter a full address, e.g. http://192.168.1.20:8000');
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      final catalog = await ApiClient(url).getProviders();
      ref.read(serverUrlProvider.notifier).set(url);
      ref.invalidate(providerCatalogProvider);
      ref.read(selectedProviderProvider.notifier).select(null);
      setState(() => _status = 'Connected: ${catalog.providers.length} image sources available.');
    } on ApiException catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server address',
            helperText: 'Emulator: http://10.0.2.2:8000 · Phone: http://<computer-ip>:8000',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _saveAndTest(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _testing ? null : _saveAndTest,
          icon: _testing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering),
          label: const Text('Save and test connection'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          Text(_status!),
        ],
      ]),
    );
  }
}
