import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import 'people_providers.dart';

class AccountMovementsScreen extends ConsumerWidget {
  const AccountMovementsScreen({super.key, required this.account});

  final PaymentAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(accountMovementsProvider(account.id));

    return Scaffold(
      appBar: AppBar(title: Text('Movimientos · ${account.label}')),
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
