import 'package:flutter_test/flutter_test.dart';

import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  setUp(() async {
    shop = TestShop();
    await shop.init();
  });
  tearDown(() => shop.close());

  Future<int> itemCost(int saleId) async {
    final items = await (shop.db.select(shop.db.saleItems)..where((i) => i.saleId.equals(saleId))).get();
    return items.fold<int>(0, (a, i) => a + i.costTotal);
  }

  group('#4 unidades vendidas sin lote', () {
    test('se costean con el último costo conocido y se avisa', () async {
      final sofa = await shop.product('Sofá', stock: 1, unitCost: 600000);
      await shop.sale(sofa); // agota el único lote

      final sale2 = await shop.sales.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      await shop.sales.addItem(saleId: sale2, productId: sofa, quantity: 2, unitPrice: 1000000);
      final warnings = await shop.sales.confirmSale(
        saleId: sale2,
        paymentLines: [const PaymentLineInput(method: 'CASH', amount: 2000000)],
      );

      expect(await itemCost(sale2), 1200000, reason: 'antes quedaba en \$0');
      expect(warnings.single.units, 2);
      expect(warnings.single.unitCost, 600000);
      expect((await shop.stock(sofa)).quantity, -2, reason: 'queda en negativo hasta ingresar');
    });

    test('mezcla: lo que alcanza sale del lote y lo demás al último costo', () async {
      final sofa = await shop.product('Sofá', stock: 1, unitCost: 500000);
      final saleId = await shop.sale(sofa, qty: 3, price: 1000000);
      expect(await itemCost(saleId), 500000 * 3);
    });

    test('producto que nunca tuvo inventario: crea la fila de stock y avisa sin costo', () async {
      final mesa = await shop.product('Mesa'); // sin ingreso
      final saleId = await shop.sales.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      await shop.sales.addItem(saleId: saleId, productId: mesa, quantity: 1, unitPrice: 300000);
      final warnings = await shop.sales.confirmSale(
        saleId: saleId,
        paymentLines: [const PaymentLineInput(method: 'CASH', amount: 300000)],
      );

      expect(warnings.single.unitCost, isNull);
      expect((await shop.stock(mesa)).quantity, -1, reason: 'antes no se registraba la salida');
    });

    test('devolver una venta con unidades sin lote deja existencias y lotes cuadrados', () async {
      final sofa = await shop.product('Sofá', stock: 1, unitCost: 600000);
      final saleId = await shop.sale(sofa, qty: 2, price: 1000000);
      expect((await shop.stock(sofa)).quantity, -1);

      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      expect((await shop.stock(sofa)).quantity, 1);
      expect(await shop.lotsRemaining(sofa), 1,
          reason: 'vuelve el lote original; la unidad sin lote no crea lote (antes quedaban 2 lotes y 1 en existencias)');
    });

    test('entregar un apartado sin inventario también avisa y costea', () async {
      final sofa = await shop.product('Sofá', stock: 1, unitCost: 700000);
      await shop.sale(sofa); // agota el lote
      final (layawayId, saleId) = await shop.invoicedLayaway(sofa);

      final warnings = await shop.layaways.setDelivered(layawayId, true);

      expect(warnings.single.unitCost, 700000);
      expect(await itemCost(saleId), 700000);
      expect((await shop.stock(sofa)).quantity, -1);
      expect((await shop.stock(sofa)).reservedQuantity, 0);
    });
  });
}
