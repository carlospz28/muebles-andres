import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';
import 'package:muebles_andres/features/expenses/expenses_providers.dart';
import 'package:muebles_andres/features/home/home_screen.dart';
import 'package:muebles_andres/features/reports/reports_providers.dart';

import 'helpers.dart';

/// Escenario único del mes: venta normal, apartado facturado y entregado,
/// y una venta devuelta en el mismo mes, más un gasto y una comisión.
Future<void> buildScenario(TestShop shop) async {
  final employee = await shop.db.into(shop.db.employees).insert(EmployeesCompanion.insert(name: 'Alcira'));
  final sofa = await shop.product('Sofá', stock: 5, unitCost: 600000);
  final comedor = await shop.product('Comedor', stock: 5, unitCost: 500000);
  final silla = await shop.product('Silla', stock: 5, unitCost: 200000);

  // Venta normal: 1.000.000, costo 600.000, comisión 5 % = 50.000.
  await shop.sale(sofa, price: 1000000, employeeId: employee, rate: 5);

  // Apartado de 800.000 facturado y entregado: costo 500.000.
  final (layawayId, _) = await shop.invoicedLayaway(comedor, price: 800000);
  await shop.layaways.setDelivered(layawayId, true);

  // Venta de 300.000 (costo 200.000) devuelta el mismo mes.
  final returned = await shop.sale(silla, price: 300000);
  await shop.sales.confirmReturn(saleId: returned, reason: 'Defecto');

  // Gasto de 70.000.
  final expenses = ExpensesRepository(shop.db);
  final cat = await expenses.saveCategory(name: 'Servicios');
  await expenses.addExpense(categoryId: cat, description: 'Luz', amount: 70000);
}

const expectedNetSales = 1000000 + 800000 + 300000 - 300000;
const expectedCost = 600000 + 500000 + 200000 - 200000;
const expectedGross = expectedNetSales - expectedCost; // 700.000
const expectedNet = expectedGross - 70000 - 50000; // 580.000

void main() {
  late TestShop shop;
  setUp(() async {
    shop = TestShop();
    await shop.init();
  });
  tearDown(() => shop.close());

  test('#5 Análisis: ventas netas y costo salen del mismo universo de ventas', () async {
    await buildScenario(shop);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(shop.db)]);
    addTearDown(container.dispose);
    container.read(reportPeriodProvider.notifier).state = ReportPeriod.month;

    final p = await container.read(profitSummaryProvider.future);
    expect(p.netSales, expectedNetSales, reason: 'antes no incluía el apartado (salía 1.000.000)');
    expect(p.cost, expectedCost);
    expect(p.utility, expectedGross, reason: 'antes daba −100.000');
    expect(p.expenses, 70000);
    expect(p.commissions, 50000);
    expect(p.netProfit, expectedNet);
  });

  test('#9 Inicio: "Utilidad" coincide con Análisis y "Flujo neto" es el flujo de caja', () async {
    await buildScenario(shop);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(shop.db)]);
    addTearDown(container.dispose);
    container.read(reportPeriodProvider.notifier).state = ReportPeriod.month;

    final home = await container.read(homeTotalsProvider.future);
    final analysis = await container.read(profitSummaryProvider.future);

    expect(home.profit.netProfit, expectedNet);
    expect(home.profit.netProfit, analysis.netProfit, reason: 'Inicio y Análisis, misma utilidad');
    expect(home.profit.utility, analysis.utility);

    // El flujo neto es plata: entró 1.000.000 + 800.000 + 300.000, salió
    // 300.000 (devolución) + 70.000 (gasto). La comisión aún no se paga.
    expect(home.netProfitPeriod, 1000000 + 800000 + 300000 - 300000 - 70000);
  });
}
