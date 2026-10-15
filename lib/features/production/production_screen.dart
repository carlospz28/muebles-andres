import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/currency_input_formatter.dart';
import '../layaways/layaways_providers.dart';
import '../people/customer_picker_dialog.dart';
import '../sales/sales_providers.dart';
import 'production_form_screen.dart';
import 'production_providers.dart';

final _productionSearchProvider = StateProvider.autoDispose<String>((ref) => '');

class ProductionScreen extends ConsumerWidget {
  const ProductionScreen({super.key});

  Future<void> _startNew(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Nueva ficha de producción'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'sale'),
            child: const Text('Vincular a una venta existente'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'layaway'),
            child: const Text('Vincular a un apartado existente'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'standalone'),
            child: const Text('Ficha independiente (sin venta todavía)'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    int? orderId;
    switch (choice) {
      case 'sale':
        orderId = await _pickSaleAndCreate(context, ref);
      case 'layaway':
        orderId = await _pickLayawayAndCreate(context, ref);
      case 'standalone':
        orderId = await _createStandalone(context, ref);
    }

    if (orderId == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductionFormScreen(orderId: orderId!)),
    );
  }

  Future<int?> _pickSaleAndCreate(BuildContext context, WidgetRef ref) async {
    final sales = await ref.read(salesWithCustomerProvider.future);
    if (!context.mounted) return null;
    if (sales.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No hay ventas registradas.')));
      return null;
    }

    var search = '';
    final picked = await showDialog<SaleListItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filtered = search.isEmpty
              ? sales
              : sales
                  .where((s) =>
                      s.customerName.toLowerCase().contains(search.toLowerCase()) ||
                      s.sale.number.contains(search))
                  .toList();
          return AlertDialog(
            title: const Text('Selecciona la venta'),
            content: SizedBox(
              width: 400,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por número o cliente...',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Sin resultados.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final s = filtered[i];
                              return ListTile(
                                title: Text('Venta ${s.sale.number} · ${s.customerName}'),
                                subtitle: Text(formatCopWithSymbol(s.sale.total)),
                                onTap: () => Navigator.pop(context, s),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null) return null;
    return ref.read(productionRepositoryProvider).createFromSale(picked.sale.id);
  }

  Future<int?> _pickLayawayAndCreate(BuildContext context, WidgetRef ref) async {
    final layaways = await ref.read(layawaysWithCustomerProvider.future);
    if (!context.mounted) return null;
    if (layaways.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No hay apartados registrados.')));
      return null;
    }

    var search = '';
    final picked = await showDialog<LayawayListItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filtered = search.isEmpty
              ? layaways
              : layaways
                  .where((l) => l.customerName.toLowerCase().contains(search.toLowerCase()))
                  .toList();
          return AlertDialog(
            title: const Text('Selecciona el apartado'),
            content: SizedBox(
              width: 400,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por cliente...',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Sin resultados.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final l = filtered[i];
                              return ListTile(
                                title: Text('Apartado #${l.layaway.id} · ${l.customerName}'),
                                onTap: () => Navigator.pop(context, l),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null) return null;
    return ref.read(productionRepositoryProvider).createFromLayaway(picked.layaway.id);
  }

  Future<int?> _createStandalone(BuildContext context, WidgetRef ref) async {
    final typeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ficha independiente'),
        content: TextField(
          controller: typeCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tipo de mueble',
            hintText: 'Ej: Comedor 6 puestos en roble',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Siguiente'),
          ),
        ],
      ),
    );
    if (confirmed != true || typeCtrl.text.trim().isEmpty || !context.mounted) return null;

    // "Cancelar" en este diálogo solo significa "sin cliente por ahora" —
    // la ficha se crea igual, el cliente se puede asignar después.
    final customer = await pickOrCreateCustomerDialog(context, ref);
    if (!context.mounted) return null;

    return ref.read(productionRepositoryProvider).createStandalone(
          productType: typeCtrl.text.trim(),
          customerId: customer?.id,
        );
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'DELIVERED':
        return 'Entregado';
      case 'CANCELLED':
        return 'Cancelado';
      default:
        return 'En proceso';
    }
  }

  Color _stateColor(String state, BuildContext context) {
    switch (state) {
      case 'DELIVERED':
        return Colors.green;
      case 'CANCELLED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(productionOrdersStreamProvider);
    final search = ref.watch(_productionSearchProvider).trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Producción')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'production',
        onPressed: () => _startNew(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva ficha'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por tipo de mueble o cliente...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(_productionSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (rows) {
                final filtered = search.isEmpty
                    ? rows
                    : rows
                        .where((row) =>
                            row.order.productType.toLowerCase().contains(search) ||
                            (row.customerName?.toLowerCase().contains(search) ?? false))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(rows.isEmpty
                        ? 'No hay fichas de producción aún.'
                        : 'Sin resultados para "$search".'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = filtered[i];
                    final o = row.order;
                    return ListTile(
                      title: Text(o.productType.isEmpty
                          ? 'Ficha #${o.id}'
                          : o.productType),
                      subtitle: Text([
                        if (row.customerName != null) row.customerName!,
                        if (o.salePrice > 0) formatCopWithSymbol(o.salePrice),
                      ].join(' · ')),
                      trailing: Chip(
                        label: Text(_stateLabel(o.state)),
                        backgroundColor:
                            _stateColor(o.state, context).withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: _stateColor(o.state, context)),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductionFormScreen(orderId: o.id),
                        ),
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
