import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

/// Todo movimiento de caja avisa de un cambio relevante para los reportes:
/// ventas, abonos de apartados, gastos, devoluciones y pagos de comisión
/// insertan una fila aquí en la misma transacción que los origina, así
/// que basta con escuchar esta tabla para que los reportes no se queden
/// "pegados" con datos viejos dentro de la misma sesión.
Stream<void> _cashMovementsTrigger(AppDatabase db) =>
    db.select(db.cashMovements).watch().map((_) {});

class DaySales {
  const DaySales(this.day, this.total);
  final DateTime day;
  final int total;
}

/// Periodo de agregación para todo el módulo de Análisis.
enum ReportPeriod { week, month, year }

final reportPeriodProvider = StateProvider<ReportPeriod>((ref) => ReportPeriod.week);

/// Rango [inicio, fin) del periodo elegido, usado por todos los reportes
/// de este módulo para que todo hable del mismo lapso de tiempo.
(DateTime, DateTime) periodRange(ReportPeriod period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 1));
  switch (period) {
    case ReportPeriod.week:
      return (today.subtract(const Duration(days: 6)), end);
    case ReportPeriod.month:
      return (DateTime(today.year, today.month, 1), end);
    case ReportPeriod.year:
      return (DateTime(today.year, 1, 1), end);
  }
}

/// Ventas agrupadas según el periodo elegido: por día (semana o mes en
/// curso) o por mes (año en curso).
final salesByPeriodProvider = StreamProvider.autoDispose<List<DaySales>>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(reportPeriodProvider);

  Future<List<DaySales>> load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    late final List<DateTime> buckets;
    late final DateTime Function(DateTime) nextBucket;

    switch (period) {
      case ReportPeriod.week:
        buckets = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
        nextBucket = (d) => d.add(const Duration(days: 1));
        break;
      case ReportPeriod.month:
        buckets = List.generate(today.day, (i) => DateTime(today.year, today.month, i + 1));
        nextBucket = (d) => d.add(const Duration(days: 1));
        break;
      case ReportPeriod.year:
        buckets = List.generate(today.month, (i) => DateTime(today.year, i + 1, 1));
        nextBucket = (d) => DateTime(d.year, d.month + 1, 1);
        break;
    }

    final results = <DaySales>[];
    for (final bucketStart in buckets) {
      final next = nextBucket(bucketStart);
      final row = await (db.selectOnly(db.cashMovements)
            ..addColumns([db.cashMovements.amount.sum()])
            ..where(db.cashMovements.type.equals('SALE') &
                db.cashMovements.date.isBiggerOrEqualValue(bucketStart) &
                db.cashMovements.date.isSmallerThanValue(next)))
          .getSingle();
      results.add(DaySales(bucketStart, row.read(db.cashMovements.amount.sum()) ?? 0));
    }
    return results;
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});

/// Ventas netas, costo y utilidad del periodo elegido — lo primero que
/// debería ver un dueño de negocio: no solo cuánto vendió, sino cuánto
/// le quedó.
class ProfitSummary {
  const ProfitSummary({required this.netSales, required this.cost});
  final int netSales;
  final int cost;
  int get utility => netSales - cost;
  double get marginPct => netSales == 0 ? 0 : (utility / netSales) * 100;
}

final profitSummaryProvider = StreamProvider.autoDispose<ProfitSummary>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(reportPeriodProvider);

  Future<ProfitSummary> load() async {
    final (start, end) = periodRange(period);

    final salesRow = await (db.selectOnly(db.cashMovements)
          ..addColumns([db.cashMovements.amount.sum()])
          ..where(db.cashMovements.type.isIn(['SALE', 'SALE_REFUND']) &
              db.cashMovements.date.isBiggerOrEqualValue(start) &
              db.cashMovements.date.isSmallerThanValue(end)))
        .getSingle();
    final netSales = salesRow.read(db.cashMovements.amount.sum()) ?? 0;

    // El costo no se revierte al devolver (la venta original se marca
    // isReturn, no se borra), así que se excluye para no inflar el costo
    // de un ingreso que ya se descontó arriba.
    final query = db.select(db.saleItems).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
    ])
      ..where(db.sales.state.equals('CONFIRMED') &
          db.sales.isReturn.equals(false) &
          db.sales.date.isBiggerOrEqualValue(start) &
          db.sales.date.isSmallerThanValue(end));
    final rows = await query.get();
    final cost = rows.fold<int>(0, (sum, row) => sum + row.readTable(db.saleItems).costTotal);

    return ProfitSummary(netSales: netSales, cost: cost);
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});

class ProductSales {
  const ProductSales(this.productName, this.quantity, this.revenue, this.cost);
  final String productName;
  final int quantity;
  final int revenue;
  final int cost;
  int get utility => revenue - cost;
  double get marginPct => revenue == 0 ? 0 : (utility / revenue) * 100;
}

/// Detalle por producto (cantidad, ventas, costo, utilidad) sobre ventas
/// confirmadas del periodo elegido.
final topProductsProvider = StreamProvider.autoDispose<List<ProductSales>>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(reportPeriodProvider);

  Future<List<ProductSales>> load() async {
    final (start, end) = periodRange(period);

    final query = db.select(db.saleItems).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
      innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
    ])
      ..where(db.sales.state.equals('CONFIRMED') &
          db.sales.date.isBiggerOrEqualValue(start) &
          db.sales.date.isSmallerThanValue(end));

    final rows = await query.get();

    final byProduct = <String, ({int qty, int revenue, int cost})>{};
    for (final row in rows) {
      final item = row.readTable(db.saleItems);
      final product = row.readTable(db.products);
      final current = byProduct[product.name] ?? (qty: 0, revenue: 0, cost: 0);
      byProduct[product.name] = (
        qty: current.qty + item.quantity,
        revenue: current.revenue + item.lineTotal,
        cost: current.cost + item.costTotal,
      );
    }

    final list = byProduct.entries
        .map((e) => ProductSales(e.key, e.value.qty, e.value.revenue, e.value.cost))
        .toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return list.take(8).toList();
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});

class EmployeeCommission {
  const EmployeeCommission(
    this.employeeId,
    this.employeeName,
    this.amount, {
    this.isActive = true,
    this.totalSales = 0,
  });
  final int employeeId;
  final String employeeName;
  final int amount;
  final bool isActive;

  /// Cuánto ha vendido en total (no la comisión, el dinero de las ventas).
  final int totalSales;
}

/// Fecha del último pago de comisión por vendedor (si ha tenido alguno).
Future<Map<int, DateTime>> _lastCommissionPaymentByEmployee(AppDatabase db) async {
  final rows = await (db.select(db.cashMovements)
        ..where((c) => c.type.equals('COMMISSION_PAYMENT') & c.refType.equals('EMPLOYEE')))
      .get();
  final lastByEmployee = <int, DateTime>{};
  for (final r in rows) {
    final current = lastByEmployee[r.refId];
    if (current == null || r.date.isAfter(current)) {
      lastByEmployee[r.refId] = r.date;
    }
  }
  return lastByEmployee;
}

/// Suma de ventas por vendedor: ventas confirmadas directas (que ya
/// incluyen las que salieron de facturar un apartado) más los abonos de
/// apartados que todavía no se han facturado — sin duplicar: un apartado
/// ya facturado deja de contarse por sus abonos porque su valor completo
/// ya quedó en la Venta que generó.
///
/// Si se pasa [sinceByEmployee] (la fecha del último pago de comisión de
/// cada vendedor), solo cuenta lo vendido DESPUÉS de esa fecha — así el
/// contador vuelve a cero apenas se le paga, para llevar mejor control de
/// lo nuevo desde el último pago.
Future<Map<int, int>> _salesTotalByEmployee(
  AppDatabase db, {
  Map<int, DateTime>? sinceByEmployee,
}) async {
  final totals = <int, int>{};

  final saleRows = await (db.select(db.sales)
        ..where((s) => s.state.equals('CONFIRMED') & s.employeeId.isNotNull()))
      .get();
  for (final s in saleRows) {
    if (s.employeeId == null) continue;
    final since = sinceByEmployee?[s.employeeId!];
    if (since != null && !s.date.isAfter(since)) continue;
    totals[s.employeeId!] = (totals[s.employeeId!] ?? 0) + s.total;
  }

  final paymentQuery = db.select(db.payments).join([
    innerJoin(db.layaways, db.layaways.id.equalsExp(db.payments.layawayId)),
  ])
    ..where(db.payments.layawayId.isNotNull() & db.layaways.state.equals('IN_PROCESS'));
  final paymentRows = await paymentQuery.get();
  for (final row in paymentRows) {
    final payment = row.readTable(db.payments);
    final layaway = row.readTable(db.layaways);
    if (layaway.employeeId == null) continue;
    final since = sinceByEmployee?[layaway.employeeId!];
    if (since != null && !payment.date.isAfter(since)) continue;
    totals[layaway.employeeId!] = (totals[layaway.employeeId!] ?? 0) + payment.totalAmount;
  }

  return totals;
}

Future<Map<int, int>> _earnedCommissionsByEmployee(
  AppDatabase db, {
  DateTime? start,
  DateTime? end,
}) async {
  final totals = <int, int>{};

  final saleQuery = db.select(db.sales)
    ..where((s) => s.state.equals('CONFIRMED') & s.employeeId.isNotNull());
  if (start != null && end != null) {
    saleQuery.where(
      (s) => s.date.isBiggerOrEqualValue(start) & s.date.isSmallerThanValue(end),
    );
  }
  final saleRows = await saleQuery.get();
  for (final s in saleRows) {
    if (s.employeeId == null) continue;
    totals[s.employeeId!] = (totals[s.employeeId!] ?? 0) + s.commissionAmount;
  }

  final paymentQuery = db.select(db.payments).join([
    innerJoin(db.layaways, db.layaways.id.equalsExp(db.payments.layawayId)),
  ])
    ..where(db.payments.layawayId.isNotNull());
  if (start != null && end != null) {
    paymentQuery.where(
      db.payments.date.isBiggerOrEqualValue(start) & db.payments.date.isSmallerThanValue(end),
    );
  }
  final paymentRows = await paymentQuery.get();
  for (final row in paymentRows) {
    final payment = row.readTable(db.payments);
    final layaway = row.readTable(db.layaways);
    if (layaway.employeeId == null) continue;
    totals[layaway.employeeId!] =
        (totals[layaway.employeeId!] ?? 0) + payment.commissionAmount;
  }

  return totals;
}

/// Suma de comisiones GANADAS por vendedor del periodo elegido (no
/// descuenta pagos ya hechos — es "cuánto generó", para el resumen de
/// Análisis). Para "cuánto le debo todavía", ver
/// [allTimeCommissionsByEmployeeProvider].
final commissionsByEmployeeProvider =
    StreamProvider.autoDispose<List<EmployeeCommission>>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(reportPeriodProvider);

  Future<List<EmployeeCommission>> load() async {
    final (start, end) = periodRange(period);
    final totals = await _earnedCommissionsByEmployee(db, start: start, end: end);
    if (totals.isEmpty) return [];

    final employees = await db.select(db.employees).get();
    final nameById = {for (final e in employees) e.id: e.name};
    final activeById = {for (final e in employees) e.id: e.isActive};

    final list = totals.entries
        .map((e) => EmployeeCommission(
              e.key,
              nameById[e.key] ?? 'Desconocido',
              e.value,
              isActive: activeById[e.key] ?? true,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});

/// Comisión PENDIENTE de pago por vendedor (ganado de siempre, menos lo
/// que ya se le ha pagado con "Pagar comisión") — no se reinicia solo;
/// baja cuando registras el pago, típicamente cada 8 días o quincena.
final allTimeCommissionsByEmployeeProvider =
    StreamProvider.autoDispose<List<EmployeeCommission>>((ref) {
  final db = ref.watch(databaseProvider);

  Future<List<EmployeeCommission>> load() async {
    final earned = await _earnedCommissionsByEmployee(db);
    final lastPaymentByEmployee = await _lastCommissionPaymentByEmployee(db);
    final salesTotals = await _salesTotalByEmployee(db, sinceByEmployee: lastPaymentByEmployee);

    final paidRows = await (db.select(db.cashMovements)
          ..where((c) => c.type.equals('COMMISSION_PAYMENT') & c.refType.equals('EMPLOYEE')))
        .get();
    final paidByEmployee = <int, int>{};
    for (final row in paidRows) {
      paidByEmployee[row.refId] = (paidByEmployee[row.refId] ?? 0) + (-row.amount);
    }

    final employeeIds = {...earned.keys, ...paidByEmployee.keys, ...salesTotals.keys};
    if (employeeIds.isEmpty) return [];

    final employees = await db.select(db.employees).get();
    final nameById = {for (final e in employees) e.id: e.name};
    final activeById = {for (final e in employees) e.id: e.isActive};

    final list = [
      for (final id in employeeIds)
        EmployeeCommission(
          id,
          nameById[id] ?? 'Desconocido',
          (earned[id] ?? 0) - (paidByEmployee[id] ?? 0),
          isActive: activeById[id] ?? true,
          totalSales: salesTotals[id] ?? 0,
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});

class ExpenseByCategory {
  const ExpenseByCategory(this.categoryName, this.amount);
  final String categoryName;
  final int amount;
}

/// Gastos por categoría del periodo elegido.
final expensesByCategoryProvider =
    StreamProvider.autoDispose<List<ExpenseByCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  final period = ref.watch(reportPeriodProvider);

  Future<List<ExpenseByCategory>> load() async {
    final (start, end) = periodRange(period);

    final query = db.select(db.expenses).join([
      innerJoin(db.expenseCategories,
          db.expenseCategories.id.equalsExp(db.expenses.categoryId)),
    ])
      ..where(db.expenses.date.isBiggerOrEqualValue(start) &
          db.expenses.date.isSmallerThanValue(end));
    final rows = await query.get();

    final byCategory = <String, int>{};
    for (final row in rows) {
      final expense = row.readTable(db.expenses);
      final category = row.readTable(db.expenseCategories);
      byCategory[category.name] = (byCategory[category.name] ?? 0) + expense.amount;
    }

    final list = byCategory.entries
        .map((e) => ExpenseByCategory(e.key, e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  return _cashMovementsTrigger(db).asyncMap((_) => load());
});
