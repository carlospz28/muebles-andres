import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';
import 'package:muebles_andres/features/reports/reports_providers.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  late int employee;
  setUp(() async {
    shop = TestShop();
    await shop.init();
    employee = await shop.db.into(shop.db.employees).insert(EmployeesCompanion.insert(name: 'Alcira'));
  });
  tearDown(() => shop.close());

  Future<int> pending() async {
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(shop.db)]);
    addTearDown(container.dispose);
    final list = await container.read(allTimeCommissionsByEmployeeProvider.future);
    return list.where((c) => c.employeeId == employee).fold<int>(0, (a, c) => a + c.amount);
  }

  test('#10 una venta devuelta deja de generar comisión', () async {
    final sofa = await shop.product('Sofá', stock: 2);
    await shop.sale(sofa, price: 1000000, employeeId: employee, rate: 5);
    final returned = await shop.sale(sofa, price: 1000000, employeeId: employee, rate: 5);
    expect(await pending(), 100000);

    await shop.sales.confirmReturn(saleId: returned, reason: 'Defecto');
    expect(await pending(), 50000, reason: 'antes seguía en 100.000');
  });

  test('#10 los abonos de un apartado devuelto dejan de generar comisión', () async {
    final sofa = await shop.product('Sofá', stock: 1);
    final layawayId = await shop.layaways.createDraft(
        customerId: shop.customerId, warehouseId: shop.warehouseId, employeeId: employee);
    await shop.layaways.addItem(layawayId: layawayId, productId: sofa, quantity: 1, unitPrice: 1000000);
    await shop.layaways.addPayment(
      layawayId: layawayId,
      paymentLines: [const PaymentLineInput(method: 'CASH', amount: 400000)],
      commissionRate: 5,
    );
    expect(await pending(), 20000);

    await shop.layaways.returnLayaway(layawayId: layawayId, reason: 'Se arrepintió');
    expect(await pending(), 0, reason: 'antes seguía en 20.000');
  });

  test('#10 la venta de un apartado facturado y devuelto tampoco deja comisión', () async {
    final sofa = await shop.product('Sofá', stock: 1);
    final (_, saleId) = await shop.invoicedLayaway(sofa, employeeId: employee, rate: 5);
    expect(await pending(), 50000);

    await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');
    expect(await pending(), 0);
  });
}
