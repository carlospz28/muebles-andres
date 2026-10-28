import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';
import '../../core/widgets/month_navigator.dart';
import '../cash/cash_providers.dart';
import '../inventory/catalog_providers.dart';
import '../people/people_providers.dart';
import '../reports/reports_providers.dart'
    show ProfitSummary, ReportPeriod, loadProfit, periodRange, profitTrigger;

/// Periodo de la tarjeta "Ventas del periodo" en Inicio, independiente del
/// que se usa en Análisis o Auditoría.
final homePeriodProvider = StateProvider.autoDispose<ReportPeriod>((ref) => ReportPeriod.month);

/// Qué mes se está revisando cuando el periodo es "Mes" — no siempre el
/// actual, para poder revisar cómo fue un mes anterior.
final homeSelectedMonthProvider = StateProvider.autoDispose<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// Se recalcula cada vez que cambia caja, apartados, la base del día, el
/// periodo o el mes elegido, para que las tarjetas de Inicio no se queden
/// "congeladas" en lo que había al abrir la app (Inicio vive en un
/// IndexedStack que no se reconstruye al cambiar de pestaña).
final homeTotalsProvider = StreamProvider.autoDispose<_HomeTotalsSnapshot>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(homePeriodProvider);
  final selectedMonth = ref.watch(homeSelectedMonthProvider);
  final trigger = StreamGroup.merge<void>([
    profitTrigger(db),
    db.select(db.layaways).watch().map((_) {}),
    db.select(db.cashSessions).watch().map((_) {}),
  ]);
  final (periodStart, periodEnd) = period == ReportPeriod.week
      ? periodRange(ReportPeriod.week)
      : monthRange(selectedMonth);
  return trigger.asyncMap((_) => _loadTotals(db, periodStart, periodEnd));
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inicio', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          const Expanded(child: _HomeBody()),
        ],
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  Future<void> _editOpeningCash(
    BuildContext context,
    WidgetRef ref,
    int currentValue,
  ) async {
    final ctrl = TextEditingController(
      text: currentValue > 0 ? formatCop(currentValue) : '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajustar caja'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cuánto efectivo hay ahora. No se reinicia cada día — solo '
                'ajústalo si hace falta corregirlo (ej. hiciste un conteo '
                'físico de la caja).',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(labelText: 'Base', prefixText: '\$ '),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final amount = ThousandsInputFormatter.parse(ctrl.text);
    await ref.read(cashRepositoryProvider).setOpeningCash(
          date: DateTime.now(),
          amount: amount,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeTotalsProvider).value;
    final period = ref.watch(homePeriodProvider);
    final selectedMonth = ref.watch(homeSelectedMonthProvider);
    final accountBalances = ref.watch(accountBalancesProvider).value ?? const [];
    final totalConsignaciones =
        accountBalances.fold<int>(0, (sum, b) => sum + b.balance);
    final inventoryValue = ref.watch(inventoryCostValueProvider).value ?? 0;
    final periodLabel = period == ReportPeriod.week
        ? 'esta semana'
        : '${monthNames[selectedMonth.month - 1]} ${selectedMonth.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Semana'),
              selected: period == ReportPeriod.week,
              onSelected: (_) =>
                  ref.read(homePeriodProvider.notifier).state = ReportPeriod.week,
            ),
            ChoiceChip(
              label: const Text('Mes'),
              selected: period == ReportPeriod.month,
              onSelected: (_) =>
                  ref.read(homePeriodProvider.notifier).state = ReportPeriod.month,
            ),
            if (period == ReportPeriod.month)
              MonthNavigator(
                month: selectedMonth,
                onChanged: (m) => ref.read(homeSelectedMonthProvider.notifier).state = m,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 4 : 2,
            childAspectRatio: 1.3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _KpiCard(
                label: 'Ventas de hoy',
                value: formatCopWithSymbol(data?.salesToday ?? 0),
                icon: Icons.today,
              ),
              _KpiCard(
                label: 'Ventas de $periodLabel',
                value: formatCopWithSymbol(data?.salesPeriod ?? 0),
                icon: Icons.calendar_month,
              ),
              _KpiCard(
                label: 'Utilidad de $periodLabel',
                value: formatCopWithSymbol(data?.profit.netProfit ?? 0),
                icon: Icons.trending_up,
                subtitle: 'Ventas netas − costo − gastos − comisiones',
                valueColor: (data?.profit.netProfit ?? 0) < 0
                    ? Theme.of(context).colorScheme.error
                    : Colors.green,
              ),
              _KpiCard(
                label: 'Flujo neto de $periodLabel',
                value: formatCopWithSymbol(data?.netProfitPeriod ?? 0),
                icon: Icons.swap_vert,
                subtitle: 'Entradas menos todas las salidas de plata (incluye compras de mercancía)',
                valueColor: (data?.netProfitPeriod ?? 0) < 0
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              _KpiCard(
                label: 'Caja disponible hoy',
                value: formatCopWithSymbol(data?.cashToday ?? 0),
                icon: Icons.savings_outlined,
                subtitle: 'Base: ${formatCopWithSymbol(data?.openingCash ?? 0)} · Editar',
                onTap: () => _editOpeningCash(context, ref, data?.openingCash ?? 0),
              ),
              _KpiCard(
                label: 'Apartados activos',
                value: '${data?.activeLayaways ?? 0}',
                icon: Icons.event_available_outlined,
              ),
              _KpiCard(
                label: 'Total en consignaciones',
                value: formatCopWithSymbol(totalConsignaciones),
                icon: Icons.account_balance_outlined,
              ),
              _KpiCard(
                label: 'Inventario (a costo)',
                value: formatCopWithSymbol(inventoryValue),
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeTotalsSnapshot {
  const _HomeTotalsSnapshot({
    required this.salesToday,
    required this.salesPeriod,
    required this.netProfitPeriod,
    required this.profit,
    required this.cashToday,
    required this.openingCash,
    required this.activeLayaways,
  });
  final int salesToday;
  final int salesPeriod;

  /// Flujo neto del periodo: entradas menos salidas de plata (ventas y
  /// abonos, menos gastos, compras a proveedores, comisiones y
  /// devoluciones). NO es la utilidad: comprar mercancía lo baja.
  final int netProfitPeriod;

  /// Utilidad del periodo, con la misma regla de Análisis y Finanzas.
  final ProfitSummary profit;
  final int cashToday;
  final int openingCash;
  final int activeLayaways;
}

Future<_HomeTotalsSnapshot> _loadTotals(
  AppDatabase db,
  DateTime periodStart,
  DateTime periodEnd,
) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);

  Future<int> sumSince(
    DateTime since, {
    String? type,
    String? method,
    String? excludeType,
    DateTime? until,
  }) async {
    final query = db.selectOnly(db.cashMovements)
      ..addColumns([db.cashMovements.amount.sum()])
      ..where(db.cashMovements.date.isBiggerOrEqualValue(since));
    if (until != null) {
      query.where(db.cashMovements.date.isSmallerThanValue(until));
    }
    if (type != null) {
      query.where(db.cashMovements.type.equals(type));
    }
    if (excludeType != null) {
      query.where(db.cashMovements.type.equals(excludeType).not());
    }
    if (method != null) {
      query.where(db.cashMovements.method.equals(method));
    }
    final row = await query.getSingle();
    return row.read(db.cashMovements.amount.sum()) ?? 0;
  }

  // Ventas = ingresos totales (efectivo + consignación), es la cifra de
  // negocio.
  final salesToday = await sumSince(startOfDay, type: 'SALE');
  final salesPeriod = await sumSince(periodStart, type: 'SALE', until: periodEnd);

  // Flujo neto = todo lo que entró menos todo lo que salió (ventas,
  // abonos, gastos, compras a proveedores, comisiones, devoluciones).
  // Se excluye el retiro de una cuenta de consignación porque no es plata
  // nueva — es la misma plata del negocio pasando del banco a la caja, no
  // debe sumarse como si fuera una entrada extra.
  final netProfitPeriod = await sumSince(
    periodStart,
    until: periodEnd,
    excludeType: 'ACCOUNT_WITHDRAWAL',
  );

  // La base de caja NO se reinicia cada día: se usa la última que se haya
  // guardado como punto de partida y se le suma el efectivo movido desde
  // ese momento (ver loadCashAvailable). "Editar" es para corregirla con
  // un conteo físico, no algo que haya que repetir todos los días.
  final cash = await loadCashAvailable(db);

  final layawayRow = await (db.selectOnly(db.layaways)
        ..addColumns([db.layaways.id.count()])
        ..where(db.layaways.state.equals('IN_PROCESS')))
      .getSingle();
  final activeLayaways = layawayRow.read(db.layaways.id.count()) ?? 0;

  return _HomeTotalsSnapshot(
    salesToday: salesToday,
    salesPeriod: salesPeriod,
    netProfitPeriod: netProfitPeriod,
    profit: await loadProfit(db, periodStart, periodEnd),
    cashToday: cash.amount,
    openingCash: cash.openingCash,
    activeLayaways: activeLayaways,
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: valueColor ?? scheme.primary),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: valueColor),
              ),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
