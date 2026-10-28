import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/currency_input_formatter.dart';
import '../../core/widgets/month_navigator.dart';
import '../reports/reports_providers.dart' show ReportPeriod, periodRange;
import 'audit_providers.dart';

final _auditFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Qué mes se está revisando cuando el periodo es "Este mes" — no siempre
/// el actual, para poder revisar cómo fue un mes anterior.
final _auditSelectedMonthProvider = StateProvider.autoDispose<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// Auditoría: todo lo que ha salido de caja por gastos, compras a
/// proveedores y pagos de comisión, en un solo lugar y en orden
/// cronológico, para poder revisar rápido en qué se fue la plata.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(auditEntriesProvider);
    final filter = ref.watch(_auditFilterProvider);
    final period = ref.watch(auditPeriodProvider);
    final selectedMonth = ref.watch(_auditSelectedMonthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (allEntries) {
          var entries =
              filter == null ? allEntries : allEntries.where((e) => e.category == filter).toList();
          if (period != null) {
            final (start, end) =
                period == ReportPeriod.week ? periodRange(period) : monthRange(selectedMonth);
            entries = entries
                .where((e) => !e.date.isBefore(start) && e.date.isBefore(end))
                .toList();
          }
          final totals = auditTotals(entries);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todo'),
                      selected: filter == null,
                      onSelected: (_) => ref.read(_auditFilterProvider.notifier).state = null,
                    ),
                    for (final c in AuditCategory.all)
                      ChoiceChip(
                        label: Text(c),
                        selected: filter == c,
                        onSelected: (_) => ref.read(_auditFilterProvider.notifier).state = c,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Siempre'),
                      selected: period == null,
                      onSelected: (_) => ref.read(auditPeriodProvider.notifier).state = null,
                    ),
                    ChoiceChip(
                      label: const Text('Esta semana'),
                      selected: period == ReportPeriod.week,
                      onSelected: (_) =>
                          ref.read(auditPeriodProvider.notifier).state = ReportPeriod.week,
                    ),
                    ChoiceChip(
                      label: const Text('Mes'),
                      selected: period == ReportPeriod.month,
                      onSelected: (_) =>
                          ref.read(auditPeriodProvider.notifier).state = ReportPeriod.month,
                    ),
                    if (period == ReportPeriod.month)
                      MonthNavigator(
                        month: selectedMonth,
                        onChanged: (m) =>
                            ref.read(_auditSelectedMonthProvider.notifier).state = m,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (filter != AuditCategory.purchase)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            filter == null ? 'Total salido (plata real)' : 'Total en $filter',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            formatCopWithSymbol(totals.outflow),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    if (filter == null || filter == AuditCategory.purchase)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Compras (compromiso, no se suma: su pago va en "Pago a proveedor")'),
                          Text(formatCopWithSymbol(totals.committed)),
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Sin movimientos todavía.'))
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          return ListTile(
                            leading: Icon(switch (e.category) {
                              'Gasto' => Icons.receipt_long_outlined,
                              AuditCategory.purchase => Icons.local_shipping_outlined,
                              AuditCategory.supplierPayment => Icons.payments_outlined,
                              'Comisión' => Icons.percent,
                              _ => Icons.attach_money,
                            }),
                            title: Text(e.description),
                            subtitle: Text(
                              '${e.category} · '
                              '${e.date.day.toString().padLeft(2, '0')}/'
                              '${e.date.month.toString().padLeft(2, '0')}/${e.date.year}',
                            ),
                            trailing: Text(
                              e.isOutflow
                                  ? '-${formatCopWithSymbol(e.amount)}'
                                  : formatCopWithSymbol(e.amount),
                              style: TextStyle(
                                fontWeight: e.isOutflow ? FontWeight.bold : null,
                                color: e.isOutflow
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.outline,
                              ),
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
