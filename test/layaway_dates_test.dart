import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/features/cash/cash_providers.dart';
import 'package:muebles_andres/features/reports/reports_providers.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  setUp(() async {
    shop = TestShop();
    await shop.init();
  });
  tearDown(() => shop.close());

  final old = DateTime(2026, 3, 15, 12);
  final oldAbono = DateTime(2026, 4, 2, 12);

  test('se puede poner la fecha real de un apartado viejo, nunca futura', () async {
    final id = await shop.layaways.createDraft(
        customerId: shop.customerId, warehouseId: shop.warehouseId, date: old);
    expect((await shop.layaway(id)).date, old);

    await shop.layaways.setDate(id, DateTime(2026, 2, 1, 12));
    expect((await shop.layaway(id)).date, DateTime(2026, 2, 1, 12));
    await expectLater(shop.layaways.setDate(id, DateTime.now().add(const Duration(days: 2))), throwsStateError);
  });

  test('un abono viejo queda con su fecha y no infla la caja ni las ventas de hoy', () async {
    // La caja se contó hoy en $0 (el efectivo de ese abono ya se gastó o
    // está dentro de lo contado).
    await CashRepository(shop.db).setOpeningCash(date: DateTime.now(), amount: 0);

    final sofa = await shop.product('Sofá', stock: 1);
    final id = await shop.layaways.createDraft(
        customerId: shop.customerId, warehouseId: shop.warehouseId, date: old);
    await shop.layaways.addItem(layawayId: id, productId: sofa, quantity: 1, unitPrice: 1000000);
    await shop.layaways.addPayment(
      layawayId: id,
      paymentLines: [const PaymentLineInput(method: 'CASH', amount: 1000000)],
      date: oldAbono,
    );

    final payment = (await shop.db.select(shop.db.payments).get()).single;
    expect(payment.date, oldAbono);
    final move = (await shop.db.select(shop.db.cashMovements).get()).single;
    expect(move.date, oldAbono, reason: 'el movimiento de caja también queda en su fecha');
    expect((await loadCashAvailable(shop.db)).amount, 0, reason: 'no suma a la caja de hoy');

    // Al facturarlo hoy, la venta queda con la fecha del último abono.
    final saleId = await shop.layaways.invoiceToSale(id);
    final sale = await (shop.db.select(shop.db.sales)..where((s) => s.id.equals(saleId))).getSingle();
    expect(sale.date, oldAbono);
    final today = DateTime.now();
    final startToday = DateTime(today.year, today.month, today.day);
    final todayProfit = await loadProfit(shop.db, startToday, startToday.add(const Duration(days: 1)));
    expect(todayProfit.netSales, 0, reason: 'no aparece como venta de hoy');
    final april = await loadProfit(shop.db, DateTime(2026, 4, 1), DateTime(2026, 5, 1));
    expect(april.netSales, 1000000);
  });

  test('el abono no puede tener fecha futura', () async {
    final sofa = await shop.product('Sofá', stock: 1);
    final id = await shop.layaways.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
    await shop.layaways.addItem(layawayId: id, productId: sofa, quantity: 1, unitPrice: 1000000);
    await expectLater(
      shop.layaways.addPayment(
        layawayId: id,
        paymentLines: [const PaymentLineInput(method: 'CASH', amount: 1000)],
        date: DateTime.now().add(const Duration(days: 3)),
      ),
      throwsStateError,
    );
  });
}
