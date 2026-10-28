import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  late int kitId;
  setUp(() async {
    shop = TestShop();
    await shop.init();
    kitId = await shop.db.into(shop.db.kits).insert(KitsCompanion.insert(name: 'Comedor 4 puestos'));
  });
  tearDown(() => shop.close());

  group('#12 kits todo o nada', () {
    test('venta: si una línea del kit falla a la mitad, no queda ninguna', () async {
      final mesa = await shop.product('Mesa');
      final saleId = await shop.sales.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);

      // La segunda línea apunta a un producto que no existe: falla al
      // insertar, después de haber insertado la primera.
      await expectLater(
        shop.sales.addKitLines(saleId: saleId, kitId: kitId, lines: [
          KitLine(productId: mesa, quantity: 1, unitPrice: 500000),
          const KitLine(productId: 99999, quantity: 4, unitPrice: 100000),
        ]),
        throwsA(anything),
      );
      expect(await shop.db.select(shop.db.saleItems).get(), isEmpty);
      final sale = await (shop.db.select(shop.db.sales)..where((s) => s.id.equals(saleId))).getSingle();
      expect(sale.total, 0);
    });

    test('apartado: si una línea del kit falla, no queda ni la línea ni su reserva', () async {
      final mesa = await shop.product('Mesa', stock: 2);
      final layawayId = await shop.layaways.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);

      await expectLater(
        shop.layaways.addKitLines(layawayId: layawayId, kitId: kitId, lines: [
          KitLine(productId: mesa, quantity: 1, unitPrice: 500000),
          const KitLine(productId: 99999, quantity: 4, unitPrice: 100000),
        ]),
        throwsA(anything),
      );
      expect(await shop.db.select(shop.db.layawayItems).get(), isEmpty);
      expect((await shop.stock(mesa)).reservedQuantity, 0, reason: 'la reserva de la mesa no queda colgada');
    });
  });

  group('#12 el repositorio valida el estado', () {
    test('no se puede agregar, quitar ni cambiar comisión en una venta confirmada', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final saleId = await shop.sale(sofa);
      final item = (await shop.db.select(shop.db.saleItems).get()).single;

      await expectLater(
        shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 1, unitPrice: 1000),
        throwsStateError,
      );
      await expectLater(shop.sales.removeItem(item.id, saleId), throwsStateError);
      await expectLater(shop.sales.setCommissionRate(saleId, 3), throwsStateError);
      expect((await shop.db.select(shop.db.saleItems).get()).length, 1);
    });

    test('no se puede modificar ni abonar un apartado facturado', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final (layawayId, _) = await shop.invoicedLayaway(sofa);
      final item = (await shop.db.select(shop.db.layawayItems).get()).single;

      await expectLater(
        shop.layaways.addItem(layawayId: layawayId, productId: sofa, quantity: 1, unitPrice: 1000),
        throwsStateError,
      );
      await expectLater(shop.layaways.removeItem(item.id), throwsStateError);
      await expectLater(
        shop.layaways.addPayment(
          layawayId: layawayId,
          paymentLines: [const PaymentLineInput(method: 'CASH', amount: 1000)],
        ),
        throwsStateError,
      );
      expect((await shop.stock(sofa)).reservedQuantity, 1);
    });
  });
}
