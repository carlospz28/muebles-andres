import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/errors.dart';
import '../../core/format/currency_input_formatter.dart';
import '../reports/reports_providers.dart';
import 'employees_screen.dart';
import 'people_providers.dart';

class CommissionsScreen extends StatelessWidget {
  const CommissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comisiones'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Vendedores'),
              Tab(text: 'Reporte de comisiones'),
              Tab(text: 'Historial de pagos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            EmployeesScreen(),
            _CommissionsReportTab(),
            _CommissionPaymentsHistoryTab(),
          ],
        ),
      ),
    );
  }
}

class _CommissionsReportTab extends ConsumerWidget {
  const _CommissionsReportTab();

  Future<void> _payCommission(
    BuildContext context,
    WidgetRef ref,
    EmployeeCommission c,
  ) async {
    final amountCtrl = TextEditingController(text: formatCop(c.amount));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pagar comisión a ${c.employeeName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pendiente: ${formatCopWithSymbol(c.amount)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(labelText: 'Monto a pagar', prefixText: '\$ '),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar pago'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final amount = ThousandsInputFormatter.parse(amountCtrl.text);
    if (amount <= 0) return;

    if (!context.mounted) return;
    final ok = await runOrShowError(
      context,
      () => ref.read(peopleRepositoryProvider).payCommission(
            employeeId: c.employeeId,
            amount: amount,
          ),
    );

    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pago registrado: ${formatCopWithSymbol(amount)} a ${c.employeeName} '
            '— descontado de caja.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionsAsync = ref.watch(allTimeCommissionsByEmployeeProvider);

    return commissionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (commissions) {
        if (commissions.isEmpty) {
          return const Center(
            child: Text('Aún no hay comisiones generadas por ventas o abonos.'),
          );
        }
        final total = commissions.fold<int>(0, (sum, c) => sum + c.amount);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Pendiente por pagar: ${formatCopWithSymbol(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final c in commissions)
              ListTile(
                leading: const Icon(Icons.percent),
                title: Text(c.employeeName),
                subtitle: Text(
                  [
                    'Total vendido: ${formatCopWithSymbol(c.totalSales)}',
                    if (!c.isActive) 'Inactivo — ya no se le pueden asignar ventas nuevas',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatCopWithSymbol(c.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (c.amount > 0) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _payCommission(context, ref, c),
                        child: const Text('Pagar'),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommissionPaymentsHistoryTab extends ConsumerWidget {
  const _CommissionPaymentsHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(commissionPaymentsHistoryProvider);

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (payments) {
        if (payments.isEmpty) {
          return const Center(
            child: Text('Aún no se ha registrado ningún pago de comisión.'),
          );
        }
        final total = payments.fold<int>(0, (sum, p) => sum + p.amount);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Total pagado: ${formatCopWithSymbol(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final p in payments)
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: Text(p.employeeName),
                subtitle: Text(
                  '${p.date.day.toString().padLeft(2, '0')}/'
                  '${p.date.month.toString().padLeft(2, '0')}/${p.date.year}',
                ),
                trailing: Text(
                  formatCopWithSymbol(p.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        );
      },
    );
  }
}
