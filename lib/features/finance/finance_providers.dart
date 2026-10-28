import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../reports/reports_providers.dart' show loadProfit;

/// Módulo de Finanzas (Flujo de caja, Estado de resultados, Balance y
/// Activos fijos), traducido del módulo de "Muebles Gestor" pero calculado
/// con las mismas reglas que ya usa el resto de esta app, para que sus
/// números coincidan con Inicio, Análisis y Auditoría:
/// - la plata sale siempre del libro mayor (CashMovements);
/// - el costo de ventas es el costo FIFO real guardado en cada venta;
/// - la caja no se reinicia cada día: es la última base guardada más todo
///   el efectivo movido desde esa fecha.

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// Cualquier cambio en estas tablas recalcula las pantallas de Finanzas.
Stream<void> _financeTrigger(AppDatabase db) => StreamGroup.merge<void>([
      db.select(db.cashMovements).watch().map((_) {}),
      db.select(db.cashSessions).watch().map((_) {}),
      db.select(db.sales).watch().map((_) {}),
      db.select(db.saleItems).watch().map((_) {}),
      db.select(db.saleReturns).watch().map((_) {}),
      db.select(db.expenses).watch().map((_) {}),
      db.select(db.layaways).watch().map((_) {}),
      db.select(db.payments).watch().map((_) {}),
      db.select(db.purchases).watch().map((_) {}),
      db.select(db.supplierPayments).watch().map((_) {}),
      db.select(db.productLots).watch().map((_) {}),
      db.select(db.fixedAssets).watch().map((_) {}),
      db.select(db.accountWithdrawals).watch().map((_) {}),
    ]);

/// Efectivo que había en caja justo antes de [moment]: la última base de
/// caja registrada hasta ese momento más todo lo que se movió en efectivo
/// desde esa base. Es la misma regla de "Caja disponible" de Inicio.
Future<int> cashAt(AppDatabase db, DateTime moment) async {
  final session = await (db.select(db.cashSessions)
        ..where((s) => s.date.isSmallerOrEqualValue(moment))
        ..orderBy([(s) => OrderingTerm.desc(s.date)])
        ..limit(1))
      .getSingleOrNull();
  final base = session?.openingCash ?? 0;
  final since = session?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
  final row = await (db.selectOnly(db.cashMovements)
        ..addColumns([db.cashMovements.amount.sum()])
        ..where(db.cashMovements.method.equals('CASH') &
            db.cashMovements.date.isBiggerOrEqualValue(since) &
            db.cashMovements.date.isSmallerThanValue(moment)))
      .getSingle();
  return base + (row.read(db.cashMovements.amount.sum()) ?? 0);
}

String methodLabel(String method) {
  switch (method) {
    case 'CASH':
      return 'Efectivo';
    case 'CONSIGNMENT':
      return 'Consignación';
    case 'SUPPLIER':
      return 'Directo a proveedor';
    default:
      return method;
  }
}

// =========================================================== FLUJO DE CAJA

final cashFlowDateProvider = StateProvider<DateTime>((ref) => dayStart(DateTime.now()));

class CashFlowData {
  CashFlowData({
    required this.date,
    required this.openingCash,
    required this.closingCash,
    required this.savedOpening,
    required this.sales,
    required this.layawayPayments,
    required this.otherIncomes,
    required this.internalMoves,
    required this.supplierPayments,
    required this.outflows,
  });
  final DateTime date;

  /// Efectivo al empezar el día.
  final int openingCash;

  /// Efectivo al terminar el día (o ahora, si es hoy).
  final int closingCash;

  /// Base de caja guardada exactamente para este día, si existe.
  final int? savedOpening;

  final List<CashMovement> sales;
  final List<CashMovement> layawayPayments;

  /// Otros ingresos reales (no ventas ni abonos).
  final List<CashMovement> otherIncomes;

  /// Movimiento interno: plata del negocio que pasa del banco a la caja
  /// (retiros de consignación). Cambia el efectivo pero NO es un ingreso.
  final List<CashMovement> internalMoves;
  final List<CashMovement> supplierPayments;

  /// Gastos, devoluciones y pagos de comisión.
  final List<CashMovement> outflows;

  static int _sum(List<CashMovement> l) => l.fold(0, (a, m) => a + m.amount);

  int get ingresosVentas => _sum(sales);
  int get ingresosAbonos => _sum(layawayPayments);
  int get otrosIngresos => _sum(otherIncomes);
  int get movimientoInterno => _sum(internalMoves);

  /// Ingresos reales del día (sin los movimientos internos).
  int get totalIn => ingresosVentas + ingresosAbonos + otrosIngresos;
  int get egresosCaja => -_sum(outflows);
  int get egresosProveedores => -_sum(supplierPayments);
  int get totalOut => egresosCaja + egresosProveedores;

  /// Entradas y salidas de todo el día separadas por forma de pago.
  Map<String, int> get netByMethod {
    final m = <String, int>{};
    for (final x in [...sales, ...layawayPayments, ...otherIncomes, ...internalMoves, ...supplierPayments, ...outflows]) {
      m[x.method] = (m[x.method] ?? 0) + x.amount;
    }
    return m;
  }
}

final cashFlowProvider = StreamProvider.autoDispose<CashFlowData>((ref) {
  final db = ref.watch(databaseProvider);
  final date = ref.watch(cashFlowDateProvider);

  Future<CashFlowData> load() async {
    final start = dayStart(date);
    final end = start.add(const Duration(days: 1));
    final moves = await (db.select(db.cashMovements)
          ..where((m) => m.date.isBiggerOrEqualValue(start) & m.date.isSmallerThanValue(end))
          ..orderBy([(m) => OrderingTerm.desc(m.date), (m) => OrderingTerm.desc(m.id)]))
        .get();
    final saved = await (db.select(db.cashSessions)..where((s) => s.date.equals(start))).getSingleOrNull();

    return CashFlowData(
      date: start,
      openingCash: await cashAt(db, start),
      closingCash: await cashAt(db, end),
      savedOpening: saved?.openingCash,
      sales: moves.where((m) => m.type == 'SALE').toList(),
      layawayPayments: moves.where((m) => m.type == 'LAYAWAY_PAYMENT').toList(),
      otherIncomes: moves
          .where((m) =>
              m.amount > 0 &&
              !const {'SALE', 'LAYAWAY_PAYMENT', 'ACCOUNT_WITHDRAWAL', 'SUPPLIER_PAYMENT'}.contains(m.type))
          .toList(),
      internalMoves: moves.where((m) => m.type == 'ACCOUNT_WITHDRAWAL').toList(),
      supplierPayments: moves.where((m) => m.type == 'SUPPLIER_PAYMENT').toList(),
      outflows: moves.where((m) => m.amount < 0 && m.type != 'SUPPLIER_PAYMENT').toList(),
    );
  }

  return _financeTrigger(db).asyncMap((_) => load());
});

// ===================================================== ESTADO DE RESULTADOS

enum IncomeMode { day, month, range, all }

class IncomePeriod {
  const IncomePeriod(this.mode, this.start, this.end);
  final IncomeMode mode;

  /// Primer día incluido.
  final DateTime start;

  /// Último día incluido.
  final DateTime end;
}

/// null = todavía no se eligió: se usa el día de la última venta, igual que
/// el original.
final incomePeriodProvider = StateProvider<IncomePeriod?>((ref) => null);

class DayResult {
  DayResult(this.date, this.ventas, this.costo);
  final DateTime date;
  final int ventas;
  final int costo;
  int get utilidad => ventas - costo;
  double get margen => ventas > 0 ? utilidad * 100 / ventas : 0;
}

class ProductResult {
  ProductResult(this.name, this.qty, this.ventas, this.costo);
  final String name;
  final int qty;
  final int ventas;
  final int costo;
  int get utilidad => ventas - costo;
  double get margen => ventas > 0 ? utilidad * 100 / ventas : 0;
}

class IncomeStatementData {
  IncomeStatementData({
    required this.period,
    required this.grossSales,
    required this.totalReturns,
    required this.costOfSales,
    required this.salesByDay,
    required this.productRows,
    required this.undeliveredLayawaySales,
  });
  final IncomePeriod period;
  final int grossSales;
  final int totalReturns;
  final int costOfSales;
  final List<DayResult> salesByDay;
  final List<ProductResult> productRows;

  /// Ventas generadas desde apartados que todavía no se han entregado: su
  /// costo se registra al entregarlas, así que por ahora suman costo cero.
  final int undeliveredLayawaySales;

  int get netSales => grossSales - totalReturns;
  int get grossProfit => netSales - costOfSales;
  double get grossMarginPct => netSales > 0 ? grossProfit * 100 / netSales : 0;
}

final incomeStatementProvider = StreamProvider.autoDispose<IncomeStatementData>((ref) {
  final db = ref.watch(databaseProvider);
  final chosen = ref.watch(incomePeriodProvider);

  Future<IncomeStatementData> load() async {
    final confirmed = await (db.select(db.sales)
          ..where((s) => s.state.equals('CONFIRMED'))
          ..orderBy([(s) => OrderingTerm.asc(s.date)]))
        .get();
    final today = dayStart(DateTime.now());
    final defaultStart = confirmed.isEmpty ? today : dayStart(confirmed.first.date);
    final defaultEnd = confirmed.isEmpty ? today : dayStart(confirmed.last.date);
    final period = chosen ?? IncomePeriod(IncomeMode.day, defaultEnd, defaultEnd);
    final (start, end) = period.mode == IncomeMode.all
        ? (defaultStart, defaultEnd.add(const Duration(days: 1)))
        : (period.start, period.end.add(const Duration(days: 1)));
    final effective = period.mode == IncomeMode.all
        ? IncomePeriod(IncomeMode.all, defaultStart, defaultEnd)
        : period;

    // Ventas (por fecha de venta).
    final sales = confirmed.where((s) => !s.date.isBefore(start) && s.date.isBefore(end)).toList();
    final gross = sales.fold<int>(0, (a, s) => a + s.total);

    // Devoluciones (por fecha de devolución), por lo que de verdad se devolvió.
    final returns = await (db.select(db.saleReturns)
          ..where((r) =>
              r.state.equals('CONFIRMED') & r.date.isBiggerOrEqualValue(start) & r.date.isSmallerThanValue(end)))
        .get();
    final totalReturns = returns.fold<int>(0, (a, r) => a + r.refundAmount);

    // Costo FIFO real de cada ítem, por fecha de venta. Lo devuelto se resta
    // en la fecha de la devolución (regla única de loadProfit, la misma de
    // Análisis e Inicio).
    final saleIds = {for (final s in sales) s.id};
    final saleById = {for (final s in sales) s.id: s};
    final items = saleIds.isEmpty
        ? <TypedResult>[]
        : await (db.select(db.saleItems).join([
            innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
          ])
                ..where(db.saleItems.saleId.isIn(saleIds)))
            .get();

    final costByDay = <DateTime, int>{};
    final byProduct = <String, ProductResult>{};
    for (final r in items) {
      final it = r.readTable(db.saleItems);
      final p = r.readTable(db.products);
      final itemCost = it.costTotal;
      final d = dayStart(saleById[it.saleId]!.date);
      costByDay[d] = (costByDay[d] ?? 0) + itemCost;
      final prev = byProduct[p.name];
      byProduct[p.name] = ProductResult(
        p.name,
        (prev?.qty ?? 0) + it.quantity,
        (prev?.ventas ?? 0) + it.lineTotal,
        (prev?.costo ?? 0) + itemCost,
      );
    }

    final salesByDayMap = <DateTime, int>{};
    for (final s in sales) {
      final d = dayStart(s.date);
      salesByDayMap[d] = (salesByDayMap[d] ?? 0) + s.total;
    }
    final days = salesByDayMap.keys.toList()..sort();

    // Ventas que vienen de apartados aún sin entregar (costo pendiente).
    final undelivered = await (db.select(db.layaways)
          ..where((l) => l.state.equals('INVOICED') & l.delivered.equals(false) & l.saleId.isNotNull()))
        .get();
    final undeliveredInPeriod = undelivered.where((l) => saleIds.contains(l.saleId)).length;

    return IncomeStatementData(
      period: effective,
      grossSales: gross,
      totalReturns: totalReturns,
      costOfSales: (await loadProfit(db, start, end)).cost,
      salesByDay: [for (final d in days) DayResult(d, salesByDayMap[d]!, costByDay[d] ?? 0)],
      productRows: byProduct.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      undeliveredLayawaySales: undeliveredInPeriod,
    );
  }

  return _financeTrigger(db).asyncMap((_) => load());
});

// ================================================================= BALANCE

final balanceDateProvider = StateProvider<DateTime>((ref) => dayStart(DateTime.now()));

class LayawayDebt {
  LayawayDebt(this.layawayId, this.customer, this.date, this.total, this.paid);
  final int layawayId;
  final String customer;
  final DateTime date;
  final int total;
  final int paid;
  int get balance => total - paid > 0 ? total - paid : 0;
}

class SupplierDebt {
  SupplierDebt(this.name, this.amount);
  final String name;
  final int amount;
}

class BalanceData {
  BalanceData({
    required this.date,
    required this.efectivo,
    required this.consignaciones,
    required this.layawaysConSaldo,
    required this.anticiposClientes,
    required this.inventarioValor,
    required this.fixedAssets,
    required this.proveedores,
    required this.commissionsTotal,
  });
  final DateTime date;
  final int efectivo;
  final int consignaciones;
  final List<LayawayDebt> layawaysConSaldo;
  final int anticiposClientes;
  final int inventarioValor;
  final List<FixedAsset> fixedAssets;
  final List<SupplierDebt> proveedores;
  final int commissionsTotal;

  int get cuentasPorCobrar => layawaysConSaldo.fold(0, (a, l) => a + l.balance);
  int get activosFijosCosto => fixedAssets.fold(0, (a, f) => a + f.cost);
  int get activosFijosLibros => fixedAssets.fold(0, (a, f) => a + bookValue(f));
  int get proveedoresPendiente => proveedores.fold(0, (a, p) => a + p.amount);

  int get totalActivos => efectivo + consignaciones + cuentasPorCobrar + inventarioValor + activosFijosLibros;
  int get totalPasivos => proveedoresPendiente + anticiposClientes;
  int get patrimonio => totalActivos - totalPasivos;
}

/// Valor en libros de un activo fijo: costo menos depreciación, nunca
/// negativo.
int bookValue(FixedAsset a) {
  final v = a.cost - a.accumulatedDepreciation;
  return v < 0 ? 0 : v;
}

final balanceProvider = StreamProvider.autoDispose<BalanceData>((ref) {
  final db = ref.watch(databaseProvider);
  final date = ref.watch(balanceDateProvider);

  Future<BalanceData> load() async {
    final end = dayStart(date).add(const Duration(days: 1));

    // Efectivo al final del día, con la misma regla de Inicio.
    final efectivo = await cashAt(db, end);

    // Consignaciones (lo que hay en las cuentas del banco) hasta la fecha.
    final consLines = await (db.select(db.paymentLines).join([
      innerJoin(db.payments, db.payments.id.equalsExp(db.paymentLines.paymentId)),
    ])
          ..where(db.paymentLines.method.equals('CONSIGNMENT') & db.payments.date.isSmallerThanValue(end)))
        .get();
    var consignaciones = consLines.fold<int>(0, (a, r) => a + r.readTable(db.paymentLines).amount);
    final consSupplier = await (db.select(db.supplierPayments)
          ..where((p) => p.method.equals('CONSIGNMENT') & p.date.isSmallerThanValue(end)))
        .get();
    consignaciones -= consSupplier.fold<int>(0, (a, p) => a + p.amount);
    final withdrawals =
        await (db.select(db.accountWithdrawals)..where((w) => w.date.isSmallerThanValue(end))).get();
    consignaciones -= withdrawals.fold<int>(0, (a, w) => a + w.amount);
    final consExpenses = await (db.select(db.expenses)
          ..where((e) => e.method.equals('CONSIGNMENT') & e.date.isSmallerThanValue(end)))
        .get();
    consignaciones -= consExpenses.fold<int>(0, (a, e) => a + e.amount);

    // Apartados en proceso: saldo pendiente (por cobrar) y abonos
    // recibidos (anticipos de clientes, un pasivo hasta que se entregue).
    final layaways = await (db.select(db.layaways).join([
      innerJoin(db.customers, db.customers.id.equalsExp(db.layaways.customerId)),
    ])
          ..where(db.layaways.state.equals('IN_PROCESS') & db.layaways.date.isSmallerThanValue(end)))
        .get();
    final layawayDebts = <LayawayDebt>[];
    var anticipos = 0;
    for (final r in layaways) {
      final l = r.readTable(db.layaways);
      final total = await (db.selectOnly(db.layawayItems)
            ..addColumns([db.layawayItems.lineTotal.sum()])
            ..where(db.layawayItems.layawayId.equals(l.id)))
          .map((x) => x.read(db.layawayItems.lineTotal.sum()) ?? 0)
          .getSingle();
      final paid = await (db.selectOnly(db.payments)
            ..addColumns([db.payments.totalAmount.sum()])
            ..where(db.payments.layawayId.equals(l.id) & db.payments.date.isSmallerThanValue(end)))
          .map((x) => x.read(db.payments.totalAmount.sum()) ?? 0)
          .getSingle();
      anticipos += paid;
      final debt = LayawayDebt(l.id, r.readTable(db.customers).name, l.date, total, paid);
      if (debt.balance > 0) layawayDebts.add(debt);
    }

    // Inventario a costo (lotes FIFO que quedan). Como en el original, es
    // el inventario actual: no se reconstruye a una fecha pasada.
    final lots = await db.select(db.productLots).get();
    final inventario = lots.fold<int>(0, (a, l) => a + l.quantityRemaining * l.unitCost);

    final assets = await (db.select(db.fixedAssets)..orderBy([(a) => OrderingTerm.asc(a.name)])).get();

    // Proveedores: compras confirmadas menos lo pagado al confirmar y los
    // abonos sueltos, hasta la fecha (misma regla de Proveedores).
    final suppliers = await db.select(db.suppliers).get();
    final purchases = await (db.select(db.purchases)
          ..where((p) => p.state.equals('CONFIRMED') & p.date.isSmallerThanValue(end)))
        .get();
    final standalone = await (db.select(db.supplierPayments)
          ..where((p) => p.purchaseId.isNull() & p.date.isSmallerThanValue(end)))
        .get();
    final proveedores = <SupplierDebt>[];
    for (final s in suppliers) {
      final opening = s.openingBalance;
      final bought = purchases.where((p) => p.supplierId == s.id).fold<int>(0, (a, p) => a + p.total);
      final paidAtConfirm = purchases.where((p) => p.supplierId == s.id).fold<int>(0, (a, p) => a + p.paidAmount);
      final paidLater = standalone.where((p) => p.supplierId == s.id).fold<int>(0, (a, p) => a + p.amount);
      final debt = opening + bought - paidAtConfirm - paidLater;
      if (debt > 0) proveedores.add(SupplierDebt(s.name, debt));
    }
    proveedores.sort((a, b) => b.amount.compareTo(a.amount));

    // Comisiones generadas por las ventas hasta la fecha (informativo).
    final commRow = await (db.selectOnly(db.sales)
          ..addColumns([db.sales.commissionAmount.sum()])
          ..where(db.sales.state.equals('CONFIRMED') & db.sales.date.isSmallerThanValue(end)))
        .getSingle();

    return BalanceData(
      date: dayStart(date),
      efectivo: efectivo,
      consignaciones: consignaciones,
      layawaysConSaldo: layawayDebts,
      anticiposClientes: anticipos,
      inventarioValor: inventario,
      fixedAssets: assets,
      proveedores: proveedores,
      commissionsTotal: commRow.read(db.sales.commissionAmount.sum()) ?? 0,
    );
  }

  return _financeTrigger(db).asyncMap((_) => load());
});

// =========================================================== ACTIVOS FIJOS

const fixedAssetCategories = {
  'FURNITURE': 'Mobiliario',
  'EQUIPMENT': 'Equipos',
  'VEHICLE': 'Vehículos',
  'OTHER': 'Otros',
};

final fixedAssetsProvider = StreamProvider.autoDispose<List<FixedAsset>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.fixedAssets)..orderBy([(a) => OrderingTerm.asc(a.name)])).watch();
});

class FinanceRepository {
  FinanceRepository(this._db);
  final AppDatabase _db;

  /// Guarda la caja inicial (base) de un día. Desde ese día la caja suma y
  /// resta los movimientos en efectivo (misma tabla que "Ajustar caja" de
  /// Inicio).
  Future<void> saveOpeningCash(DateTime date, int amount, String notes) async {
    // La fecha es única: si ya hay base ese día, se actualiza.
    await _db.into(_db.cashSessions).insert(
          CashSessionsCompanion.insert(
            date: dayStart(date),
            openingCash: Value(amount),
            notes: Value(notes),
          ),
          onConflict: DoUpdate(
            (_) => CashSessionsCompanion(openingCash: Value(amount), notes: Value(notes)),
            target: [_db.cashSessions.date],
          ),
        );
  }

  Future<void> saveFixedAsset({
    int? id,
    required String name,
    required String category,
    required DateTime purchaseDate,
    required int cost,
    required int accumulatedDepreciation,
    required String notes,
  }) async {
    final data = FixedAssetsCompanion(
      name: Value(name),
      category: Value(category),
      purchaseDate: Value(purchaseDate),
      cost: Value(cost),
      accumulatedDepreciation: Value(accumulatedDepreciation),
      notes: Value(notes),
    );
    if (id == null) {
      await _db.into(_db.fixedAssets).insert(data);
    } else {
      await (_db.update(_db.fixedAssets)..where((a) => a.id.equals(id))).write(data);
    }
  }

  Future<void> deleteFixedAsset(int id) =>
      (_db.delete(_db.fixedAssets)..where((a) => a.id.equals(id))).go();
}

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(databaseProvider));
});
