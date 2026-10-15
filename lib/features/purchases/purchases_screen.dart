import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';
import '../people/people_providers.dart';
import 'purchase_form_screen.dart';
import 'purchases_providers.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  Future<void> _startNewPurchase(BuildContext context, WidgetRef ref) async {
    final suppliers = await ref.read(suppliersStreamProvider.future);
    if (!context.mounted) return;

    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero registra un proveedor.')),
      );
      return;
    }

    final supplier = await showDialog<Supplier>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecciona el proveedor'),
        children: [
          for (final s in suppliers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (supplier == null || !context.mounted) return;

    final warehouse = await ref.read(defaultWarehouseProvider.future);
    final purchaseId = await ref.read(purchasesRepositoryProvider).createDraft(
          supplierId: supplier.id,
          warehouseId: warehouse.id,
        );

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PurchaseFormScreen(purchaseId: purchaseId)),
    );
  }

  Color _stateColor(String state, BuildContext context) {
    switch (state) {
      case 'CONFIRMED':
        return Colors.green;
      case 'CANCELLED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'CONFIRMED':
        return 'Confirmada';
      case 'CANCELLED':
        return 'Anulada';
      default:
        return 'Borrador';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchasesWithSupplierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'purchases',
        onPressed: () => _startNewPurchase(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva compra'),
      ),
      body: purchasesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No hay compras registradas.'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              final p = row.purchase;
              return ListTile(
                title: Text('Compra ${p.number} · ${row.supplierName}'),
                subtitle: Text(formatCopWithSymbol(p.total)),
                trailing: Chip(
                  label: Text(_stateLabel(p.state)),
                  backgroundColor: _stateColor(p.state, context).withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: _stateColor(p.state, context)),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PurchaseFormScreen(purchaseId: p.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
