import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';
import 'package:muebles_andres/features/people/people_providers.dart';
import 'package:muebles_andres/features/purchases/purchases_providers.dart';
import 'package:muebles_andres/features/reports/reports_providers.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  late int accountId;
  late int supplierId;
  late int employee;

  setUp(() async {
    shop = TestShop();
    await shop.init();
    accountId = await shop.db.into(shop.db.paymentAccounts).insert(PaymentAccountsCompanion.insert(label: 'Banco'));
    supplierId = await shop.db.into(shop.db.suppliers).insert(SuppliersCompanion.insert(name: 'Maderas'));
    employee = await shop.db.into(shop.db.employees).insert(EmployeesCompanion.insert(name: 'Alcira'));
  });
  tearDown(() => shop.close());

  /// Foto de todo lo que una venta o apartado puede mover.
  Future<Map<String, int>> snapshot(int productId) async {
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(shop.db)]);
    addTearDown(container.dispose);
    final commissions = await container.read(allTimeCommissionsByEmployeeProvider.future);
    final moves = await (shop.db.select(shop.db.stockMovements)..where((m) => m.productId.equals(productId))).get();
    final stock = await shop.stock(productId);
    return {
      'existencias': stock.quantity,
      'reservado': stock.reservedQuantity,
      'lotes': await shop.lotsRemaining(productId),
      'movimientos': moves.fold<int>(0, (a, m) => a + (m.type == 'OUT' ? -m.quantity : m.quantity)),
      'libro': await shop.ledger(),
      'cuenta': await accountBalance(shop.db, accountId),
      'deudaProveedor': await supplierDebt(shop.db, supplierId),
      'comision': commissions.fold<int>(0, (a, c) => a + c.amount),
      'ventas': (await shop.db.select(shop.db.sales).get()).length,
      'pagos': (await shop.db.select(shop.db.payments).get()).length,
    };
  }

  List<PaymentLineInput> mixed(int total) => [
        PaymentLineInput(method: 'CASH', amount: total - 500000),
        PaymentLineInput(method: 'CONSIGNMENT', amount: 300000, accountId: accountId),
        PaymentLineInput(method: 'SUPPLIER', amount: 200000, supplierId: supplierId),
      ];

  group('borrar una venta', () {
    test('confirmada (efectivo + consignación + proveedor, con comisión): todo vuelve como antes', () async {
      final sofa = await shop.product('Sofá', stock: 3);
      final before = await snapshot(sofa);

      final saleId = await shop.sale(sofa, qty: 2, price: 1000000, lines: mixed(2000000), employeeId: employee, rate: 5);
      expect((await snapshot(sofa))['existencias'], 1);

      await shop.sales.deleteSale(saleId);
      expect(await snapshot(sofa), before);
    });

    test('borrador: se borra sin tocar nada más', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final before = await snapshot(sofa);
      final saleId = await shop.sales.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      await shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 1, unitPrice: 100);

      await shop.sales.deleteSale(saleId);
      expect(await snapshot(sofa), before);
    });

    test('ya devuelta: se borra su rastro y el inventario sigue igual', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final before = await snapshot(sofa);
      final saleId = await shop.sale(sofa, lines: mixed(1000000));
      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      await shop.sales.deleteSale(saleId);
      expect(await snapshot(sofa), before);
    });

    test('con unidades vendidas sin lote: las existencias vuelven', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final before = await snapshot(sofa);
      final saleId = await shop.sale(sofa, qty: 3, price: 1000000);

      await shop.sales.deleteSale(saleId);
      expect(await snapshot(sofa), before);
    });

    test('una venta que salió de un apartado se borra desde el apartado', () async {
      final sofa = await shop.product('Sofá', stock: 1);
      final (_, saleId) = await shop.invoicedLayaway(sofa);
      await expectLater(shop.sales.deleteSale(saleId), throwsStateError);
    });
  });

  group('borrar un apartado', () {
    Future<int> layawayWithPayment(int productId, {required List<PaymentLineInput> lines}) async {
      final id = await shop.layaways.createDraft(
          customerId: shop.customerId, warehouseId: shop.warehouseId, employeeId: employee);
      await shop.layaways.addItem(layawayId: id, productId: productId, quantity: 1, unitPrice: 1000000);
      await shop.layaways.addPayment(layawayId: id, paymentLines: lines, commissionRate: 5);
      return id;
    }

    test('en proceso con abonos: libera la reserva y la plata sale por donde entró', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final before = await snapshot(sofa);
      final id = await layawayWithPayment(sofa, lines: mixed(700000));

      await shop.layaways.deleteLayaway(id);
      expect(await snapshot(sofa), before);
      expect(await shop.db.select(shop.db.layaways).get(), isEmpty);
    });

    test('facturado y entregado: la mercancía vuelve a sus lotes y se borra su venta', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final before = await snapshot(sofa);
      final id = await layawayWithPayment(sofa, lines: mixed(1000000));
      await shop.layaways.invoiceToSale(id);
      await shop.layaways.setDelivered(id, true);
      expect((await snapshot(sofa))['existencias'], 1);

      await shop.layaways.deleteLayaway(id);
      expect(await snapshot(sofa), before);
    });

    test('facturado sin entregar: libera la reserva y se borra su venta', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final before = await snapshot(sofa);
      final id = await layawayWithPayment(sofa, lines: mixed(1000000));
      await shop.layaways.invoiceToSale(id);

      await shop.layaways.deleteLayaway(id);
      expect(await snapshot(sofa), before);
    });

    test('ya devuelto (y su venta devuelta): se borra todo sin descuadrar', () async {
      final sofa = await shop.product('Sofá', stock: 2);
      final before = await snapshot(sofa);
      final id = await layawayWithPayment(sofa, lines: mixed(1000000));
      final saleId = await shop.layaways.invoiceToSale(id);
      await shop.layaways.setDelivered(id, true);
      await shop.sales.confirmReturn(saleId: saleId, reason: 'Defecto');

      await shop.layaways.deleteLayaway(id);
      expect(await snapshot(sofa), before);

      final id2 = await layawayWithPayment(sofa, lines: mixed(600000));
      await shop.layaways.returnLayaway(layawayId: id2, reason: 'Se arrepintió');
      await shop.layaways.deleteLayaway(id2);
      expect(await snapshot(sofa), before);
    });
  });
}
