import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import 'account_movements_screen.dart';
import 'people_providers.dart';

/// Cuentas bancarias/destinos de consignación: se usan tanto para registrar
/// a quién se le pagó por consignación (clientes) como para los abonos a
/// proveedores por transferencia.
class PaymentAccountsScreen extends ConsumerWidget {
  const PaymentAccountsScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {PaymentAccount? account}) {
    final labelCtrl = TextEditingController(text: account?.label ?? '');
    final bankCtrl = TextEditingController(text: account?.bankName ?? '');
    final numberCtrl = TextEditingController(text: account?.accountNumber ?? '');

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account == null ? 'Nueva cuenta' : 'Editar cuenta'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre / a quién se le consigna',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankCtrl,
                decoration: const InputDecoration(labelText: 'Banco'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numberCtrl,
                decoration: const InputDecoration(labelText: 'Número de cuenta'),
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
              final label = labelCtrl.text.trim();
              if (label.isEmpty) return;
              await ref.read(peopleRepositoryProvider).savePaymentAccount(
                    id: account?.id,
                    label: label,
                    bankName: bankCtrl.text.trim(),
                    accountNumber: numberCtrl.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(accountBalancesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cuenta'),
      ),
      body: balancesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (balances) {
          if (balances.isEmpty) {
            return const Center(
              child: Text('No hay cuentas de consignación registradas.'),
            );
          }
          final total = balances.fold<int>(0, (sum, b) => sum + b.balance);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total en consignaciones'),
                    Text(
                      formatCopWithSymbol(total),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: balances.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = balances[i];
                    final a = b.account;
                    return ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(a.label),
                      subtitle: Text([
                        if (a.bankName.isNotEmpty) a.bankName,
                        if (a.accountNumber.isNotEmpty) a.accountNumber,
                      ].join(' · ')),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AccountMovementsScreen(account: a),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar cuenta',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _openForm(context, ref, account: a),
                          ),
                          Text(
                            formatCopWithSymbol(b.balance),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Switch(
                            value: a.isActive,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) => ref
                                .read(peopleRepositoryProvider)
                                .setPaymentAccountActive(a.id, v),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
