import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import 'catalog_providers.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Product? product,
  }) async {
    final categories = await ref.read(categoriesStreamProvider.future);
    if (!context.mounted) return;

    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final descCtrl = TextEditingController(text: product?.description ?? '');
    final priceCtrl = TextEditingController(
      text: product != null ? formatCop(product.price) : '',
    );
    int? categoryId = product?.categoryId ?? categories.firstOrNull?.id;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(product == null ? 'Nuevo producto' : 'Editar producto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (product != null) ...[
                  Text('SKU: ${product.sku}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: categoryId == null
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      await ref.read(catalogRepositoryProvider).saveProduct(
                            id: product?.id,
                            name: name,
                            categoryId: categoryId!,
                            price: ThousandsInputFormatter.parse(priceCtrl.text),
                            description: descCtrl.text.trim(),
                          );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final costByProduct = ref.watch(productFifoCostProvider).value ?? const {};
    final categoryNames = {
      for (final c in categoriesAsync.value ?? <Category>[]) c.id: c.name,
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'products',
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre o SKU...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  ref.read(productSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (products) {
                if (products.isEmpty) {
                  return const Center(child: Text('No hay productos.'));
                }
                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = products[i];
                    final cost = costByProduct[p.id];
                    return ListTile(
                      leading: CircleAvatar(child: Text(p.sku)),
                      title: Text(p.name),
                      subtitle: Text(
                        '${categoryNames[p.categoryId] ?? ''} · '
                        '${cost == null ? 'Sin costo aún' : 'Costo: ${formatCopWithSymbol(cost)}'}',
                      ),
                      onTap: () => _openForm(context, ref, product: p),
                      trailing: Switch(
                        value: p.isActive,
                        onChanged: (v) => ref
                            .read(catalogRepositoryProvider)
                            .setProductActive(p.id, v),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
