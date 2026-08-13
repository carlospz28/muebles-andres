import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/providers.dart';

/// Se recalcula cada vez que cambia caja o apartados, para que las
/// tarjetas de Inicio no se queden "congeladas" en lo que había al abrir
/// la app (Inicio vive en un IndexedStack que no se reconstruye al
/// cambiar de pestaña).
final homeTotalsProvider = StreamProvider.autoDispose<_HomeTotalsSnapshot>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.cashMovements).watch().map((_) {}),
    db.select(db.layaways).watch().map((_) {}),
  ]);
  return trigger.asyncMap((_) => _loadTotals(db));
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeTotalsProvider).value;

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 4 : 2,
      childAspectRatio: 1.6,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _KpiCard(
          label: 'Ventas de hoy',
          value: formatCopWithSymbol(data?.salesToday ?? 0),
          icon: Icons.today,
        ),
        _KpiCard(
          label: 'Ventas del mes',
          value: formatCopWithSymbol(data?.salesMonth ?? 0),
          icon: Icons.calendar_month,
        ),
        _KpiCard(
          label: 'Caja disponible hoy',
          value: formatCopWithSymbol(data?.cashToday ?? 0),
          icon: Icons.savings_outlined,
        ),
        _KpiCard(
          label: 'Apartados activos',
          value: '${data?.activeLayaways ?? 0}',
          icon: Icons.event_available_outlined,
        ),
      ],
    );
  }
}

class _HomeTotalsSnapshot {
  const _HomeTotalsSnapshot({
    required this.salesToday,
    required this.salesMonth,
    required this.cashToday,
    required this.activeLayaways,
  });
  final int salesToday;
  final int salesMonth;
  final int cashToday;
  final int activeLayaways;
}

Future<_HomeTotalsSnapshot> _loadTotals(AppDatabase db) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final startOfMonth = DateTime(now.year, now.month, 1);

  Future<int> sumSince(DateTime since, {String? type, String? method}) async {
    final query = db.selectOnly(db.cashMovements)
      ..addColumns([db.cashMovements.amount.sum()])
      ..where(db.cashMovements.date.isBiggerOrEqualValue(since));
    if (type != null) {
      query.where(db.cashMovements.type.equals(type));
    }
    if (method != null) {
      query.where(db.cashMovements.method.equals(method));
    }
    final row = await query.getSingle();
    return row.read(db.cashMovements.amount.sum()) ?? 0;
  }

  // Ventas = ingresos totales (efectivo + consignación), es la cifra de
  // negocio. Caja disponible = solo el efectivo físico del cajón.
  final salesToday = await sumSince(startOfDay, type: 'SALE');
  final salesMonth = await sumSince(startOfMonth, type: 'SALE');
  final cashToday = await sumSince(startOfDay, method: 'CASH');

  final layawayRow = await (db.selectOnly(db.layaways)
        ..addColumns([db.layaways.id.count()])
        ..where(db.layaways.state.equals('IN_PROCESS')))
      .getSingle();
  final activeLayaways = layawayRow.read(db.layaways.id.count()) ?? 0;

  return _HomeTotalsSnapshot(
    salesToday: salesToday,
    salesMonth: salesMonth,
    cashToday: cashToday,
    activeLayaways: activeLayaways,
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: scheme.primary),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
