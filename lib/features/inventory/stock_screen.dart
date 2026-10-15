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

  Future<void> _removeInventory(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(stockStreamProvider.future);
    if (!context.mounted) return;

    ProductStock? selected;
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();
    var search = '';
    String? error;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final filtered = search.isEmpty
              ? rows
              : rows
                  .where((r) =>
                      r.product.name.toLowerCase().contains(search.toLowerCase()) ||
                      r.product.sku.contains(search))
                  .toList();

          return AlertDialog(
            title: const Text('Retirar inventario'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (selected == null) ...[
                      const Text(
                        'Quita unidades del inventario (dañado, extraviado, uso '
                        'interno, etc.) sin afectar la caja.',
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
                          final r = filtered[i];
                          return ListTile(
                            title: Text(r.product.name),
                            subtitle: Text(
                              'SKU ${r.product.sku} · ${r.available} disponibles',
                            ),
                            enabled: r.available > 0,
                            onTap: () => setState(() => selected = r),
                          );
                        },
                      ),
                    ] else ...[
                      ListTile(
                        title: Text(selected!.product.name),
                        subtitle: Text(
                          'SKU ${selected!.product.sku} · '
                          '${selected!.available} disponibles',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => selected = null),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cantidad a retirar'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Motivo (opcional)',
                          helperText: 'Ej: dañado, extraviado, uso interno',
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
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
                    if (qty <= 0) {
                      setState(() => error = 'Ingresa una cantidad válida.');
                      return;
                    }
                    if (qty > selected!.available) {
                      setState(() => error =
                          'Solo hay ${selected!.available} disponibles.');
                      return;
                    }

                    final warehouse = await ref.read(defaultWarehouseProvider.future);
                    await ref.read(catalogRepositoryProvider).removeInventory(
                          productId: selected!.product.id,
                          warehouseId: warehouse.id,
                          quantity: qty,
                          note: noteCtrl.text.trim(),
                        );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Retirar'),
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
      // Antes eran FloatingActionButton flotantes: al desplazar la lista
      // se quedaban tapando el número de "disponibles" a la derecha, que
      // es justo la información que más se necesita ver rápido. Como
      // barra fija abajo, la lista nunca queda oculta detrás de ellos.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _removeInventory(context, ref),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Retirar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addInventoryEntry(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Ingresar'),
                ),
              ),
            ],
          ),
        ),
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
                    // El número grande es SIEMPRE lo que hay físicamente en
                    // la bodega — un apartado reserva, pero no saca nada del
                    // almacén hasta que se entrega, así que no debe verse
                    // como si ya se hubiera descontado.
                    final shortage = r.available < 0 ? -r.available : 0;
                    final nothingFree = r.available <= 0;
                    return ListTile(
                      leading: CircleAvatar(child: Text(r.product.sku)),
                      title: Text(r.product.name),
                      subtitle: shortage > 0
                          ? Text(
                              'Faltan $shortage por conseguir para completar '
                              'los apartados',
                            )
                          : (r.reserved > 0
                              ? Text(
                                  '${r.reserved} apartado(s) sin entregar · '
                                  '${r.available} libres para vender',
                                )
                              : null),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.quantity}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: nothingFree
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Text('en bodega', style: TextStyle(fontSize: 11)),
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
