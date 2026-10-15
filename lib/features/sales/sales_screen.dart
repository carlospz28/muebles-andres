import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';
import '../people/customer_picker_dialog.dart';
import '../people/people_providers.dart';
import 'sale_form_screen.dart';
import 'sales_providers.dart';

final _saleSearchProvider = StateProvider.autoDispose<String>((ref) => '');

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  Future<void> _startNewSale(BuildContext context, WidgetRef ref) async {
    final customer = await pickOrCreateCustomerDialog(context, ref);
    if (customer == null || !context.mounted) return;

    final employees = await ref.read(activeEmployeesStreamProvider.future);
    Employee? employee;
    if (employees.isNotEmpty && context.mounted) {
      employee = await showDialog<Employee?>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('¿Quién es el vendedor?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Sin vendedor'),
            ),
            for (final e in employees)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e),
                child: Text(e.name),
              ),
          ],
        ),
      );
    }

    if (!context.mounted) return;
    final warehouse = await ref.read(defaultWarehouseProvider.future);
    final saleId = await ref.read(salesRepositoryProvider).createDraft(
          customerId: customer.id,
          warehouseId: warehouse.id,
          employeeId: employee?.id,
        );
    if (employee != null && employee.defaultCommissionRate != 0) {
      await ref
          .read(salesRepositoryProvider)
          .setCommissionRate(saleId, employee.defaultCommissionRate);
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SaleFormScreen(saleId: saleId)),
    );
  }

  Color _stateColor(Sale sale, BuildContext context) {
    if (sale.isReturn) return Theme.of(context).colorScheme.error;
    switch (sale.state) {
      case 'CONFIRMED':
        return Colors.green;
      case 'CANCELLED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  String _stateLabel(Sale sale) {
    if (sale.isReturn) return 'Devuelta';
    switch (sale.state) {
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
    final salesAsync = ref.watch(salesWithCustomerProvider);
    final search = ref.watch(_saleSearchProvider).trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Ventas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sales',
        onPressed: () => _startNewSale(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva venta'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por cliente o número de venta...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(_saleSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (rows) {
                final filtered = search.isEmpty
                    ? rows
                    : rows.where((row) {
                        return row.customerName.toLowerCase().contains(search) ||
                            row.sale.number.toLowerCase().contains(search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(rows.isEmpty
                        ? 'No hay ventas registradas.'
                        : 'Sin resultados para "$search".'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = filtered[i];
                    final s = row.sale;
                    return ListTile(
                      title: Text('Venta ${s.number} · ${row.customerName}'),
                      subtitle: Text(
                        '${formatCopWithSymbol(s.total)}'
                        '${s.state == 'CONFIRMED' ? (s.delivered ? ' · Entregada' : ' · Sin entregar') : ''}',
                      ),
                      trailing: Chip(
                        label: Text(_stateLabel(s)),
                        backgroundColor: _stateColor(s, context).withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: _stateColor(s, context)),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SaleFormScreen(saleId: s.id)),
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
