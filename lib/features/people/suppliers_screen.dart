import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/errors.dart';
import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../purchases/purchases_providers.dart';
import '../sales/payment_dialog.dart';
import 'people_providers.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {Supplier? supplier}) {
    final nameCtrl = TextEditingController(text: supplier?.name ?? '');
    final docCtrl = TextEditingController(text: supplier?.document ?? '');
    final phoneCtrl = TextEditingController(text: supplier?.phone ?? '');
    final openingBalanceCtrl = TextEditingController(
      text: supplier == null || supplier.openingBalance == 0
          ? ''
          : formatCop(supplier.openingBalance),
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier == null ? 'Nuevo proveedor' : 'Editar proveedor'),
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
                controller: docCtrl,
                decoration: const InputDecoration(labelText: 'NIT / Cédula (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: openingBalanceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Deuda inicial (opcional)',
                  helperText: 'Si ya se le debía algo antes de usar la app, '
                      'ponlo aquí para que empiece a contar desde ahí.',
                  prefixText: '\$ ',
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
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(peopleRepositoryProvider).saveSupplier(
                    id: supplier?.id,
                    name: name,
                    document: docCtrl.text.trim().isEmpty ? null : docCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    openingBalance: ThousandsInputFormatter.parse(openingBalanceCtrl.text),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _paySupplier(BuildContext context, WidgetRef ref, SupplierBalance b) async {
    final result = await showPaymentDialog(
      context,
      totalToPay: b.balance,
      title: 'Pagar a ${b.supplier.name}',
      allowPartial: true,
    );
    if (result == null || !context.mounted) return;

    await runOrShowError(
      context,
      () => ref.read(purchasesRepositoryProvider).paySupplier(
            supplierId: b.supplier.id,
            paymentLines: result.lines,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(supplierBalancesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'suppliers',
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proveedor'),
      ),
      body: balancesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (balances) {
          if (balances.isEmpty) {
            return const Center(child: Text('No hay proveedores.'));
          }
          return ListView.separated(
            itemCount: balances.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = balances[i];
              final s = b.supplier;
              return ListTile(
                title: Text(s.name),
                subtitle: Text([
                  if ((s.document ?? '').isNotEmpty) 'Doc: ${s.document}',
                  if ((s.phone ?? '').isNotEmpty) 'Tel: ${s.phone}',
                  if (b.totalPurchased > 0)
                    'Comprado ${formatCopWithSymbol(b.totalPurchased)} · '
                        'Pagado ${formatCopWithSymbol(b.totalPaid)}',
                  if (s.openingBalance > 0)
                    'Deuda inicial ${formatCopWithSymbol(s.openingBalance)}',
                ].join(' · ')),
                isThreeLine: b.totalPurchased > 0 || s.openingBalance > 0,
                onTap: () => _openForm(context, ref, supplier: s),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.balance > 0
                          ? 'Debe ${formatCopWithSymbol(b.balance)}'
                          : b.balance < 0
                              ? 'A favor ${formatCopWithSymbol(-b.balance)}'
                              : 'Al día',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: b.balance > 0
                            ? Theme.of(context).colorScheme.error
                            : Colors.green,
                      ),
                    ),
                    if (b.balance > 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _paySupplier(context, ref, b),
                        child: const Text('Pagar'),
                      ),
                    Switch(
                      value: s.isActive,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) =>
                          ref.read(peopleRepositoryProvider).setSupplierActive(s.id, v),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
