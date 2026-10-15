import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../purchases/purchases_providers.dart';
import '../sales/sales_providers.dart' show PaymentLineInput;
import 'people_providers.dart';

class AccountMovementsScreen extends ConsumerWidget {
  const AccountMovementsScreen({super.key, required this.account});

  final PaymentAccount account;

  Future<int> _currentBalance(WidgetRef ref) async {
    final balances = await ref.read(accountBalancesProvider.future);
    final match = balances.where((b) => b.account.id == account.id);
    return match.isEmpty ? 0 : match.first.balance;
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final balance = await _currentBalance(ref);
    if (!context.mounted) return;

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Retirar de la cuenta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo actual: ${formatCopWithSymbol(balance)}'),
                const SizedBox(height: 4),
                const Text(
                  'El monto retirado se suma a la caja como efectivo.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final amount = ThousandsInputFormatter.parse(amountCtrl.text);
                if (amount <= 0) {
                  setState(() => error = 'Ingresa un monto válido.');
                  return;
                }
                if (amount > balance) {
                  setState(() => error = 'Esta cuenta solo tiene ${formatCopWithSymbol(balance)}.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Retirar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await ref.read(peopleRepositoryProvider).withdrawFromAccount(
          accountId: account.id,
          amount: ThousandsInputFormatter.parse(amountCtrl.text),
          note: noteCtrl.text.trim(),
        );
  }

  Future<void> _payToSupplier(BuildContext context, WidgetRef ref) async {
    final balance = await _currentBalance(ref);
    if (!context.mounted) return;
    final suppliers = await ref.read(suppliersStreamProvider.future);
    if (!context.mounted) return;

    Supplier? selected;
    final amountCtrl = TextEditingController();
    var search = '';
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final filtered = search.isEmpty
              ? suppliers
              : suppliers
                  .where((s) => s.name.toLowerCase().contains(search.toLowerCase()))
                  .toList();

          return AlertDialog(
            title: const Text('Enviar a un proveedor'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saldo actual: ${formatCopWithSymbol(balance)}'),
                    const SizedBox(height: 12),
                    if (selected == null) ...[
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar proveedor...',
                        ),
                        onChanged: (v) => setState(() => search = v),
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          return ListTile(
                            title: Text(s.name),
                            onTap: () => setState(() => selected = s),
                          );
                        },
                      ),
                    ] else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(selected!.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => selected = null),
                        ),
                      ),
                      TextField(
                        controller: amountCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsInputFormatter()],
                        decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              if (selected != null)
                FilledButton(
                  onPressed: () {
                    final amount = ThousandsInputFormatter.parse(amountCtrl.text);
                    if (amount <= 0) {
                      setState(() => error = 'Ingresa un monto válido.');
                      return;
                    }
                    if (amount > balance) {
                      setState(
                          () => error = 'Esta cuenta solo tiene ${formatCopWithSymbol(balance)}.');
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Enviar'),
                ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || selected == null) return;

    await ref.read(purchasesRepositoryProvider).paySupplier(
      supplierId: selected!.id,
      paymentLines: [
        PaymentLineInput(
          method: 'CONSIGNMENT',
          amount: ThousandsInputFormatter.parse(amountCtrl.text),
          accountId: account.id,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(accountMovementsProvider(account.id));

    return Scaffold(
      appBar: AppBar(title: Text('Movimientos · ${account.label}')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'accountPayToSupplier',
            onPressed: () => _payToSupplier(context, ref),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('A proveedor'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'accountWithdraw',
            onPressed: () => _withdraw(context, ref),
            icon: const Icon(Icons.arrow_upward),
            label: const Text('Retirar'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ],
      ),
      body: movementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (movements) {
          if (movements.isEmpty) {
            return const Center(
              child: Text('Aún no hay movimientos en esta cuenta.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: movements.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = movements[i];
              final positive = m.amount >= 0;
              return ListTile(
                leading: Icon(
                  positive ? Icons.arrow_downward : Icons.arrow_upward,
                  color: positive ? Colors.green : Colors.red,
                ),
                title: Text(m.description),
                subtitle: Text(
                  '${m.date.day.toString().padLeft(2, '0')}/'
                  '${m.date.month.toString().padLeft(2, '0')}/${m.date.year}',
                ),
                trailing: Text(
                  '${positive ? '+' : '-'}${formatCopWithSymbol(m.amount.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: positive ? Colors.green : Colors.red,
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
