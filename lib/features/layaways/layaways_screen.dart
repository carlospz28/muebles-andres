import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';
import '../people/customer_picker_dialog.dart';
import '../people/people_providers.dart';
import 'layaway_form_screen.dart';
import 'layaways_providers.dart';

final _layawaySearchProvider = StateProvider.autoDispose<String>((ref) => '');

class LayawaysScreen extends ConsumerWidget {
  const LayawaysScreen({super.key});

  Future<void> _startNewLayaway(BuildContext context, WidgetRef ref) async {
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
    final layawayId = await ref.read(layawaysRepositoryProvider).createDraft(
          customerId: customer.id,
          warehouseId: warehouse.id,
          employeeId: employee?.id,
        );

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LayawayFormScreen(layawayId: layawayId)),
    );
  }

  Color _stateColor(String state, BuildContext context) {
    switch (state) {
      case 'INVOICED':
        return Colors.blue;
      case 'CANCELLED_NO_INVOICE':
      case 'RETURNED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'INVOICED':
        return 'Facturado';
      case 'CANCELLED_NO_INVOICE':
        return 'Cancelado';
      case 'RETURNED':
        return 'Devuelto';
      default:
        return 'En proceso';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layawaysAsync = ref.watch(layawaysWithCustomerProvider);
    final search = ref.watch(_layawaySearchProvider).trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Apartados')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'layaways',
        onPressed: () => _startNewLayaway(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo apartado'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por cliente...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(_layawaySearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: layawaysAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (rows) {
                final filtered = search.isEmpty
                    ? rows
                    : rows
                        .where((row) => row.customerName.toLowerCase().contains(search))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(rows.isEmpty
                        ? 'No hay apartados registrados.'
                        : 'Sin resultados para "$search".'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = filtered[i];
                    final l = row.layaway;
                    return Consumer(
                      builder: (context, ref, _) {
                        final totalsAsync = ref.watch(layawayTotalsProvider(l.id));
                        final totals = totalsAsync.value;
                        return ListTile(
                          title: Text('Apartado #${l.id} · ${row.customerName}'),
                          subtitle: Text(
                            totals == null
                                ? '...'
                                : 'Total ${formatCopWithSymbol(totals.total)}'
                                    '${l.state == 'IN_PROCESS' || l.state == 'INVOICED' ? ' · Saldo ${formatCopWithSymbol(totals.balance)}' : ''}'
                                    '${l.state == 'IN_PROCESS' ? (l.delivered ? ' · Entregado' : ' · Sin entregar') : ''}',
                          ),
                          trailing: Chip(
                            label: Text(_stateLabel(l.state)),
                            backgroundColor:
                                _stateColor(l.state, context).withValues(alpha: 0.15),
                            labelStyle: TextStyle(color: _stateColor(l.state, context)),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LayawayFormScreen(layawayId: l.id),
                            ),
                          ),
                        );
                      },
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
