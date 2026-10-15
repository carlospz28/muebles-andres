import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../people/people_providers.dart';
import 'expenses_providers.dart';

class ExpensesListScreen extends ConsumerWidget {
  const ExpensesListScreen({super.key});

  Future<void> _addExpense(BuildContext context, WidgetRef ref) async {
    final categories = await ref.read(expenseCategoriesStreamProvider.future);
    if (!context.mounted) return;

    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea una categoría de gasto.')),
      );
      return;
    }

    final accounts = await ref.read(paymentAccountsStreamProvider.future);
    if (!context.mounted) return;

    ExpenseCategory? category = categories.first;
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var method = 'CASH';
    PaymentAccount? account = accounts.firstOrNull;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Nuevo gasto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ExpenseCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => category = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Valor', prefixText: '\$ '),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => method = 'CASH'),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Efectivo'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: method == 'CASH'
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: accounts.isEmpty
                            ? null
                            : () => setState(() => method = 'CONSIGNMENT'),
                        icon: const Icon(Icons.account_balance_outlined),
                        label: const Text('Consignación'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: method == 'CONSIGNMENT'
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                if (method == 'CONSIGNMENT') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentAccount>(
                    initialValue: account,
                    decoration: const InputDecoration(labelText: 'Cuenta'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a, child: Text(a.label)),
                    ],
                    onChanged: (v) => setState(() => account = v),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
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
              onPressed: category == null || (method == 'CONSIGNMENT' && account == null)
                  ? null
                  : () async {
                      final amount = ThousandsInputFormatter.parse(amountCtrl.text);
                      if (amount <= 0) return;
                      await ref.read(expensesRepositoryProvider).addExpense(
                            categoryId: category!.id,
                            description: descCtrl.text.trim(),
                            amount: amount,
                            note: noteCtrl.text.trim(),
                            method: method,
                            accountId: method == 'CONSIGNMENT' ? account!.id : null,
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
    final expensesAsync = ref.watch(expensesStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expensesList',
        onPressed: () => _addExpense(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo gasto'),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No hay gastos registrados.'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              final e = row.expense;
              return ListTile(
                title: Text(e.description.isEmpty ? row.categoryName : e.description),
                subtitle: Text(
                  '${row.categoryName} · '
                  '${e.method == 'CONSIGNMENT' ? 'Consignación' : 'Efectivo'}',
                ),
                trailing: Text(
                  formatCopWithSymbol(e.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
