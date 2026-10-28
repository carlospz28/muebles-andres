import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/features/people/people_providers.dart';
import 'package:muebles_andres/features/purchases/purchases_providers.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

import 'helpers.dart';

void main() {
  late TestShop shop;
  setUp(() async {
    shop = TestShop();
    await shop.init();
  });
  tearDown(() => shop.close());

  Future<int> draft() => shop.sales.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);

  group('#11 validaciones en el repositorio', () {
    test('descuento entre 0 y cantidad × precio (ventas y apartados)', () async {
      final sofa = await shop.product('Sofá');
      final saleId = await draft();
      expect(() => shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 1, unitPrice: 100000, discount: 150000),
          throwsStateError);
      expect(() => shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 1, unitPrice: 100000, discount: -1),
          throwsStateError);
      expect(() => shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 0, unitPrice: 100000),
          throwsStateError);
      await shop.sales.addItem(saleId: saleId, productId: sofa, quantity: 2, unitPrice: 100000, discount: 200000);

      final layawayId = await shop.layaways.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      expect(() => shop.layaways.addItem(layawayId: layawayId, productId: sofa, quantity: 1, unitPrice: 100000, discount: 100001),
          throwsStateError);
    });

    test('el precio final de un kit debe ser mayor que cero', () async {
      final silla = await shop.product('Silla');
      final saleId = await draft();
      // "Precio final del kit" borrado (0): todo el valor se volvía descuento.
      await expectLater(
        shop.sales.addKitLines(saleId: saleId, kitId: 1, lines: [
          KitLine(productId: silla, quantity: 4, unitPrice: 100000, discount: 400000),
        ]),
        throwsStateError,
      );
      expect(await (shop.db.select(shop.db.saleItems)).get(), isEmpty);
    });

    test('% de comisión entre 0 y 100', () async {
      final saleId = await draft();
      expect(() => shop.sales.setCommissionRate(saleId, -5), throwsStateError);
      expect(() => shop.sales.setCommissionRate(saleId, 150), throwsStateError);
      await shop.sales.setCommissionRate(saleId, 5);

      final layawayId = await shop.layaways.createDraft(customerId: shop.customerId, warehouseId: shop.warehouseId);
      expect(
        () => shop.layaways.addPayment(
          layawayId: layawayId,
          paymentLines: [const PaymentLineInput(method: 'CASH', amount: 1000)],
          commissionRate: -1,
        ),
        throwsStateError,
      );
      expect(() => PeopleRepository(shop.db).saveEmployee(name: 'X', defaultCommissionRate: -2), throwsStateError);
    });

    test('retiro ≤ saldo de la cuenta', () async {
      final account = await shop.db.into(shop.db.paymentAccounts).insert(PaymentAccountsCompanion.insert(label: 'Banco'));
      final sofa = await shop.product('Sofá', stock: 1);
      await shop.sale(sofa, price: 500000, lines: [PaymentLineInput(method: 'CONSIGNMENT', amount: 500000, accountId: account)]);
      final people = PeopleRepository(shop.db);

      await expectLater(people.withdrawFromAccount(accountId: account, amount: 600000), throwsStateError);
      await people.withdrawFromAccount(accountId: account, amount: 500000);
      expect(await accountBalance(shop.db, account), 0);
    });

    test('pago de comisión ≤ lo pendiente', () async {
      final employee = await shop.db.into(shop.db.employees).insert(EmployeesCompanion.insert(name: 'Alcira'));
      final sofa = await shop.product('Sofá', stock: 1);
      await shop.sale(sofa, price: 1000000, employeeId: employee, rate: 5); // 50.000
      final people = PeopleRepository(shop.db);

      await expectLater(people.payCommission(employeeId: employee, amount: 60000), throwsStateError);
      await people.payCommission(employeeId: employee, amount: 50000);
      await expectLater(people.payCommission(employeeId: employee, amount: 1), throwsStateError);
    });

    test('abono a proveedor ≤ lo que se le debe', () async {
      final supplier = await shop.db.into(shop.db.suppliers).insert(
          SuppliersCompanion.insert(name: 'Maderas', openingBalance: const Value(300000)));
      final purchases = PurchasesRepository(shop.db);

      await expectLater(
        purchases.paySupplier(supplierId: supplier, paymentLines: [const PaymentLineInput(method: 'CASH', amount: 300001)]),
        throwsStateError,
      );
      await purchases.paySupplier(supplierId: supplier, paymentLines: [const PaymentLineInput(method: 'CASH', amount: 300000)]);
      expect(await supplierDebt(shop.db, supplier), 0);
    });
  });
}
