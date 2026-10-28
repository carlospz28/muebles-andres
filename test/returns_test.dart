import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  setUp(() async {
    shop = TestShop();
    await shop.init();
  });
  tearDown(() => shop.close());

  group('#2 devolver la venta de un apartado facturado', () {
    test('el apartado queda Devuelto y ya no se puede entregar ni descuenta inventario', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final (layawayId, saleId) = await shop.invoicedLayaway(sofa);
      expect((await shop.stock(sofa)).reservedQuantity, 1);

      await shop.sales.confirmReturn(saleId: saleId, reason: 'No le gustó');

      expect((await shop.layaway(layawayId)).state, 'RETURNED');
      expect((await shop.stock(sofa)).reservedQuantity, 0, reason: 'se libera la reserva');

      await expectLater(shop.layaways.setDelivered(layawayId, true), throwsStateError);
      final stock = await shop.stock(sofa);
      expect(stock.quantity, 2, reason: 'no salió mercancía');
      expect(await shop.lotsRemaining(sofa), 2);
      expect((await shop.layaway(layawayId)).delivered, isFalse);
    });
  });

  group('#3 la devolución sale por las mismas formas de pago', () {
    late int accountId;
    late int supplierId;

    setUp(() async {
      accountId = await shop.db.into(shop.db.paymentAccounts).insert(PaymentAccountsCompanion.insert(label: 'Bancolombia'));
      supplierId = await shop.db.into(shop.db.suppliers).insert(SuppliersCompanion.insert(name: 'Maderas'));
    });

    /// Saldo de la cuenta como lo calcula Consignaciones (líneas por
    /// consignación − pagos a proveedor − retiros − gastos).
    Future<int> accountBalance() async {
      final lines = await (shop.db.select(shop.db.paymentLines)
            ..where((l) => l.method.equals('CONSIGNMENT') & l.accountId.equals(accountId)))
          .get();
      return lines.fold<int>(0, (a, l) => a + l.amount);
    }

    Future<int> supplierPaid() async {
      final rows = await (shop.db.select(shop.db.supplierPayments)..where((p) => p.supplierId.equals(supplierId))).get();
      return rows.fold<int>(0, (a, p) => a + p.amount);
    }

    test('venta mixta efectivo + consignación: cada parte vuelve a su lugar', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final saleId = await shop.sale(sofa, lines: [
        const PaymentLineInput(method: 'CASH', amount: 300000),
        PaymentLineInput(method: 'CONSIGNMENT', amount: 700000, accountId: accountId),
      ]);
      expect(await shop.ledger(method: 'CASH'), 300000);
      expect(await accountBalance(), 700000);

      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      expect(await shop.ledger(method: 'CASH'), 0, reason: 'antes la caja quedaba en −700.000');
      expect(await shop.ledger(method: 'CONSIGNMENT'), 0);
      expect(await accountBalance(), 0, reason: 'la cuenta devuelve sus 700.000');
      final refunds = await (shop.db.select(shop.db.cashMovements)..where((m) => m.type.equals('SALE_REFUND'))).get();
      expect({for (final r in refunds) r.method: r.amount}, {'CASH': -300000, 'CONSIGNMENT': -700000});
    });

    test('venta pagada directo a proveedor: se revierte el abono y no toca caja ni banco', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final saleId = await shop.sale(sofa, lines: [
        PaymentLineInput(method: 'SUPPLIER', amount: 1000000, supplierId: supplierId),
      ]);
      expect(await supplierPaid(), 1000000);

      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      expect(await supplierPaid(), 0, reason: 'la deuda con el proveedor vuelve a subir');
      expect(await shop.ledger(method: 'CASH'), 0);
      expect(await shop.ledger(method: 'SUPPLIER'), 0);
      expect(await accountBalance(), 0);
    });

    test('devolver un apartado abonado por consignación devuelve desde la cuenta', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final layawayId = await shop.layaways.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      await shop.layaways.addItem(layawayId: layawayId, productId: sofa, quantity: 1, unitPrice: 1000000);
      await shop.layaways.addPayment(layawayId: layawayId, paymentLines: [
        const PaymentLineInput(method: 'CASH', amount: 100000),
        PaymentLineInput(method: 'CONSIGNMENT', amount: 400000, accountId: accountId),
      ]);

      await shop.layaways.returnLayaway(layawayId: layawayId, reason: 'Se arrepintió');

      expect(await shop.ledger(method: 'CASH'), 0);
      expect(await accountBalance(), 0);
      final refunds = await (shop.db.select(shop.db.cashMovements)..where((m) => m.type.equals('LAYAWAY_REFUND'))).get();
      expect(refunds.fold<int>(0, (a, r) => a + r.amount), -500000);
    });

    test('devolver la venta de un apartado facturado devuelve por las formas de los abonos', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final (_, saleId) = await shop.invoicedLayaway(sofa, lines: [
        PaymentLineInput(method: 'CONSIGNMENT', amount: 1000000, accountId: accountId),
      ]);
      expect(await accountBalance(), 1000000);

      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      expect(await accountBalance(), 0);
      expect(await shop.ledger(method: 'CASH'), 0, reason: 'antes salía 1.000.000 de la caja');
    });
  });
}
