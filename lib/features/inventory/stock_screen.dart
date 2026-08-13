import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';
import 'catalog_providers.dart';

class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  Future<void> _addInventoryEntry(BuildContext context, WidgetRef ref) async {
    final products = await ref.read(productsStreamProvider.future);
    if (!context.mounted) return;

    Product? selected;
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController();
    final transportCtrl = TextEditingController();
    var search = '';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final filtered = search.isEmpty
              ? products
              : products
                  .where((p) =>
                      p.name.toLowerCase().contains(search.toLowerCase()) ||
                      p.sku.contains(search))
                  .toList();

          return AlertDialog(
            title: const Text('Ingresar inventario'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected == null) ...[
                    const Text(
                      'Suma stock directo sin afectar la caja ni generar deuda '
                      'con ningún proveedor — para lo que ya había físicamente '
                      'o entradas que no son una compra formal.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
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
                          subtitle: Text('SKU ${p.sku}'),
                          onTap: () => setState(() => selected = p),
                        );
                      },
                    ),
                  ] else ...[
                    ListTile(
                      title: Text(selected!.name),
                      subtitle: Text('SKU ${selected!.sku}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => selected = null),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: costCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Costo unitario',
                        prefixText: '\$ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: transportCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Costo de transporte (opcional, total)',
                        helperText: 'Se reparte entre las unidades para calcular '
                            'bien la ganancia.',
                        prefixText: '\$ ',
                      ),
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
                    final cost = ThousandsInputFormatter.parse(costCtrl.text);
                    final transport = ThousandsInputFormatter.parse(transportCtrl.text);
                    if (qty <= 0 || cost <= 0) return;

                    final warehouse = await ref.read(defaultWarehouseProvider.future);
                    await ref.read(catalogRepositoryProvider).addInventoryEntry(
                          productId: selected!.id,
                          warehouseId: warehouse.id,
                          quantity: qty,
                          unitCost: cost,
                          transportCost: transport,
                        );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Ingresar'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addInventoryEntry(context, ref),
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Ingresar inventario'),
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
              onChanged: (v) => ref.read(productSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: stockAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(child: Text('No hay productos activos.'));
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final low = r.available <= 0;
                    return ListTile(
                      leading: CircleAvatar(child: Text(r.product.sku)),
                      title: Text(r.product.name),
                      subtitle: r.reserved > 0
                          ? Text('${r.reserved} reservado(s) por apartados')
                          : null,
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.available}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: low
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Text('disponibles', style: TextStyle(fontSize: 11)),
                        ],
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
