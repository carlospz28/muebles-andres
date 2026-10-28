import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';
import 'package:muebles_andres/features/cash/cash_providers.dart';
import 'package:muebles_andres/features/finance/finance_providers.dart';

void main() {
  test('guardar la caja inicial dos veces el mismo día la actualiza (no falla)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = FinanceRepository(db);
    final day = DateTime(2026, 10, 20);
    await repo.saveOpeningCash(day, 100000, '');
    await repo.saveOpeningCash(day, 250000, 'conteo');
    final rows = await db.select(db.cashSessions).get();
    expect(rows.length, 1);
    expect(rows.single.openingCash, 250000);

    // Efectivo: base + movimientos en efectivo desde ese día (no los de
    // consignación).
    await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        type: 'SALE', amount: 50000, refType: 'SALE', refId: 1, date: Value(DateTime(2026, 10, 20, 10))));
    await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        type: 'SALE',
        amount: 70000,
        method: const Value('CONSIGNMENT'),
        refType: 'SALE',
        refId: 2,
        date: Value(DateTime(2026, 10, 20, 11))));
    await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        type: 'EXPENSE', amount: -20000, refType: 'EXPENSE', refId: 1, date: Value(DateTime(2026, 10, 21, 9))));
    expect(await cashAt(db, DateTime(2026, 10, 20)), 250000);
    expect(await cashAt(db, DateTime(2026, 10, 21)), 300000);
    expect(await cashAt(db, DateTime(2026, 10, 22)), 280000);
    await db.close();
  });

  test('"Ajustar caja" de Inicio (hora real) y Finanzas ven la misma caja', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = CashRepository(db);
    await repo.setOpeningCash(date: DateTime(2026, 10, 20, 9), amount: 100000);
    await repo.setOpeningCash(date: DateTime(2026, 10, 20, 15), amount: 120000);
    // Cada ajuste queda con su hora; manda el último.
    expect((await db.select(db.cashSessions).get()).length, 2);
    final now = DateTime(2026, 10, 20, 18);
    expect(await cashAt(db, now), 120000);
    expect((await loadCashAvailable(db)).amount, 120000);
    await db.close();
  });

  /// Calcula Finanzas sobre una COPIA de una base real y lo compara con
  /// la regla de "Caja disponible" de Inicio.
  /// `INSPECT_DB=copia.sqlite flutter test test/finance_test.dart`
  final path = Platform.environment['INSPECT_DB'];
  test('Finanzas con datos reales', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File(path!)));
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    final flow = await container.read(cashFlowProvider.future);
    final income = await container.read(incomeStatementProvider.future);
    container.read(incomePeriodProvider.notifier).state =
        IncomePeriod(IncomeMode.all, DateTime(2020), DateTime(2020));
    final incomeAll = await container.read(incomeStatementProvider.future);
    final balance = await container.read(balanceProvider.future);

    // Regla de Inicio: última base + todo el efectivo desde esa base.
    final session = await (db.select(db.cashSessions)
          ..orderBy([(s) => OrderingTerm.desc(s.date)])
          ..limit(1))
        .getSingleOrNull();
    final since = session?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cashRow = await (db.selectOnly(db.cashMovements)
          ..addColumns([db.cashMovements.amount.sum()])
          ..where(db.cashMovements.method.equals('CASH') & db.cashMovements.date.isBiggerOrEqualValue(since)))
        .getSingle();
    final homeCash = (session?.openingCash ?? 0) + (cashRow.read(db.cashMovements.amount.sum()) ?? 0);

    final lots = await db.select(db.productLots).get();
    final inventory = lots.fold<int>(0, (a, l) => a + l.quantityRemaining * l.unitCost);

    // ignore: avoid_print
    print('''
FLUJO ${flow.date}: inicial ${flow.openingCash} | ingresos ${flow.totalIn} (ventas ${flow.ingresosVentas}, abonos ${flow.ingresosAbonos}, otros ${flow.otrosIngresos}) | salidas ${flow.totalOut} (caja ${flow.egresosCaja}, proveedores ${flow.egresosProveedores}) | final ${flow.closingCash}
RESULTADOS (${income.period.mode} ${income.period.start}): brutas ${income.grossSales} dev ${income.totalReturns} netas ${income.netSales} costo ${income.costOfSales} utilidad ${income.grossProfit} margen ${income.grossMarginPct.toStringAsFixed(2)}% · dias ${income.salesByDay.length} productos ${income.productRows.length}
RESULTADOS TODO (${incomeAll.period.start} - ${incomeAll.period.end}): brutas ${incomeAll.grossSales} dev ${incomeAll.totalReturns} netas ${incomeAll.netSales} costo ${incomeAll.costOfSales} utilidad ${incomeAll.grossProfit} · apartados sin entregar ${incomeAll.undeliveredLayawaySales}
BALANCE ${balance.date}: efectivo ${balance.efectivo} (Inicio: $homeCash) consig ${balance.consignaciones} cxc ${balance.cuentasPorCobrar} inv ${balance.inventarioValor} (lotes: $inventory) af ${balance.activosFijosLibros} | prov ${balance.proveedoresPendiente} anticipos ${balance.anticiposClientes} | activos ${balance.totalActivos} pasivos ${balance.totalPasivos} patrimonio ${balance.patrimonio}''');

    expect(balance.efectivo, homeCash, reason: 'el efectivo del Balance debe ser la Caja disponible de Inicio');
    expect(balance.inventarioValor, inventory);
    expect(flow.closingCash, homeCash, reason: 'hoy, la caja al cierre es la caja disponible');
    expect(income.netSales, income.grossSales - income.totalReturns);
    await db.close();
  }, skip: path == null ? 'Falta INSPECT_DB' : false);
}
