import 'package:flutter_test/flutter_test.dart';

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
}
