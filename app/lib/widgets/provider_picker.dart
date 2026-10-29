import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';

/// Bottom sheet listing providers from `GET /api/providers`. [onSelected] defaults to
/// just storing the choice.
Future<void> showProviderPicker(BuildContext context, WidgetRef ref,
    {void Function(String key)? onSelected}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ProviderPickerSheet(
      onSelected: (key) {
        Navigator.of(context).pop();
        (onSelected ?? ref.read(selectedProviderProvider.notifier).select)(key);
      },
    ),
  );
}

class ProviderPickerSheet extends ConsumerWidget {
  const ProviderPickerSheet({super.key, required this.onSelected});

  final void Function(String key) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(providerCatalogProvider);
    final selected = ref.watch(selectedProviderProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: catalog.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(e is ApiException ? e.message : 'Could not load image sources.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => ref.invalidate(providerCatalogProvider),
                  child: const Text('Retry')),
            ]),
          ),
          data: (c) => ProviderList(
            catalog: c,
            selectedKey: selected ?? c.defaultKey,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }
}

class ProviderList extends StatelessWidget {
  const ProviderList(
      {super.key, required this.catalog, required this.selectedKey, required this.onSelected});

  final ProviderCatalog catalog;
  final String selectedKey;
  final void Function(String key) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Image source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        for (final p in catalog.providers)
          ListTile(
            leading: Icon(p.key == selectedKey
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked),
            title: Text(p.name),
            subtitle: Text(
              [p.description, '${p.wavelength} · ${p.coverage}']
                  .where((s) => s.isNotEmpty)
                  .join('\n'),
            ),
            isThreeLine: true,
            trailing: p.key == catalog.defaultKey ? const Chip(label: Text('Default')) : null,
            onTap: () => onSelected(p.key),
          ),
      ],
    );
  }
}
