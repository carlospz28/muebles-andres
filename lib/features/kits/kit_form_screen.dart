import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../inventory/catalog_providers.dart';
import 'kits_providers.dart';

class KitFormScreen extends ConsumerWidget {
  const KitFormScreen({super.key, required this.kitId});

  final int kitId;

  Future<void> _editKit(BuildContext context, WidgetRef ref, Kit kit) async {
    final nameCtrl = TextEditingController(text: kit.name);
    final descCtrl = TextEditingController(text: kit.description);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar kit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(kitsRepositoryProvider).saveKit(
                    id: kit.id,
                    name: name,
                    description: descCtrl.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _addComponent(BuildContext context, WidgetRef ref) async {
    final products = await ref.read(productsStreamProvider.future);
    if (!context.mounted) return;

    Product? selected;
    final qtyCtrl = TextEditingController(text: '1');
    var includedByDefault = true;
    var search = '';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final filtered = search.isEmpty
              ? products
              : products
                  .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
                  .toList();

          return AlertDialog(
            title: const Text('Agregar componente'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected == null) ...[
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar producto...',
                      ),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final p = filtered[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(formatCopWithSymbol(p.price)),
                          onTap: () => setState(() => selected = p),
                        );
                      },
                    ),
                  ] else ...[
                    ListTile(
                      title: Text(selected!.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => selected = null),
                      ),
                    ),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad por kit'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluido por defecto'),
                      subtitle: const Text(
                        'Ej: el vidrio puede venir desmarcado si se cobra aparte.',
                      ),
                      value: includedByDefault,
                      onChanged: (v) => setState(() => includedByDefault = v),
                    ),
                  ],
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              if (selected != null)
                FilledButton(
                  onPressed: () async {
                    final qty = int.tryParse(qtyCtrl.text) ?? 0;
                    if (qty <= 0) return;
                    await ref.read(kitsRepositoryProvider).addComponent(
                          kitId: kitId,
                          productId: selected!.id,
                          defaultQuantity: qty,
                          includedByDefault: includedByDefault,
                        );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Agregar'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitAsync = ref.watch(kitByIdProvider(kitId));
    final componentsAsync = ref.watch(kitComponentsProvider(kitId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del kit')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'kitForm',
        onPressed: () => _addComponent(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Agregar componente'),
      ),
      body: kitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (kit) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: Text(kit.name, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(kit.description),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editKit(context, ref, kit),
              ),
            ),
            const Divider(),
            Text('Componentes', style: Theme.of(context).textTheme.titleMedium),
            componentsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => Text('Error: $e'),
              data: (components) {
                if (components.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Este kit aún no tiene componentes.'),
                  );
                }
                return Column(
                  children: [
                    for (final c in components)
                      ListTile(
                        title: Text(c.product.name),
                        subtitle: Text(
                          '${c.component.defaultQuantity} x ${formatCopWithSymbol(c.product.price)}',
                        ),
                        leading: Checkbox(
                          value: c.component.includedByDefault,
                          onChanged: (v) => ref
                              .read(kitsRepositoryProvider)
                              .setComponentIncludedByDefault(
                                  c.component.id, v ?? true),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref
                              .read(kitsRepositoryProvider)
                              .removeComponent(c.component.id),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
