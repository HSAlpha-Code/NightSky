import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models.dart';
import '../sensors.dart';
import '../settings.dart';
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
  SensorAvailability? _sensors;

  @override
  void initState() {
    super.initState();
    SensorAvailability.query().then((s) {
      if (mounted) setState(() => _sensors = s);
    });
  }

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
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final gyroAvailable = _sensors?.supports(SensorMode.gyro);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _SectionHeader('Sensors'),
        SwitchListTile(
          key: const Key('setting-gyro'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable gyroscope'),
          subtitle: Text(gyroAvailable == false
              ? 'This phone has no gyroscope.'
              : 'Off: accelerometer + compass only (most reliable; never flips above/below '
                  'the horizon). On: gyroscope-fused sensor, smoother but can flip or drift '
                  'on some phones.'),
          value: s.useGyroscope && gyroAvailable != false,
          onChanged: gyroAvailable == false
              ? null
              : (v) => notifier.update((s) => s.copyWith(useGyroscope: v)),
        ),
        _ChoiceSetting<SensorSmoothing>(
          title: 'Smooth sensor movement',
          values: SensorSmoothing.values,
          selected: s.smoothing,
          label: (v) => v.label,
          description: s.smoothing.description,
          onSelected: (v) => notifier.update((s) => s.copyWith(smoothing: v)),
        ),
        _ChoiceSetting<Steadiness>(
          title: 'Steadiness',
          values: Steadiness.values,
          selected: s.steadiness,
          label: (v) => v.label,
          description: 'Counts as steady when the phone moves less than '
              '${s.steadiness.maxShakeDeg}° in 0.6 s.',
          onSelected: (v) => notifier.update((s) => s.copyWith(steadiness: v)),
        ),
        SwitchListTile(
          key: const Key('setting-auto-capture'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-capture when steady'),
          subtitle: const Text('Takes the photo after holding steady for 2 seconds.'),
          value: s.autoCapture,
          onChanged: (v) => notifier.update((s) => s.copyWith(autoCapture: v)),
        ),
        SwitchListTile(
          key: const Key('setting-readout'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show altitude and heading'),
          subtitle: const Text('Where the camera points, shown over the camera view.'),
          value: s.showPointingReadout,
          onChanged: (v) => notifier.update((s) => s.copyWith(showPointingReadout: v)),
        ),
        const SizedBox(height: 8),
        const _SectionHeader('Display'),
        _ChoiceSetting<FontSize>(
          title: 'Font size',
          values: FontSize.values,
          selected: s.fontSize,
          label: (v) => v.label,
          onSelected: (v) => notifier.update((s) => s.copyWith(fontSize: v)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: s == const AppSettings() ? null : notifier.reset,
            icon: const Icon(Icons.restore),
            label: const Text('Reset to defaults'),
          ),
        ),
        const SizedBox(height: 8),
        const _SectionHeader('Server'),
        const SizedBox(height: 8),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

/// A titled row of choice chips for one enum setting.
class _ChoiceSetting<T> extends StatelessWidget {
  const _ChoiceSetting({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.description,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.bodyLarge),
        if (description != null)
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              onSelected: (_) => onSelected(v),
            ),
        ]),
      ]),
    );
  }
}
