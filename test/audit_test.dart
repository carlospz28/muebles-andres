import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';
import 'package:muebles_andres/features/audit/audit_providers.dart';
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

  test('#6 compra a crédito pagada después: el total salido la cuenta una sola vez', () async {
    final supplierId = await shop.db.into(shop.db.suppliers).insert(SuppliersCompanion.insert(name: 'Maderas'));
    final sofa = await shop.product('Sofá');
    final purchases = PurchasesRepository(shop.db);

    // Compra a crédito de 1.000.000 y luego abono de 1.000.000.
    final p1 = await purchases.createDraft(supplierId: supplierId, warehouseId: shop.warehouseId);
    await purchases.addItem(purchaseId: p1, productId: sofa, quantity: 2, unitCost: 500000);
    await purchases.confirmPurchase(p1);
    await purchases.paySupplier(
      supplierId: supplierId,
      paymentLines: [const PaymentLineInput(method: 'CASH', amount: 1000000)],
    );

    // Compra de contado de 300.000.
    final p2 = await purchases.createDraft(supplierId: supplierId, warehouseId: shop.warehouseId);
    await purchases.addItem(purchaseId: p2, productId: sofa, quantity: 1, unitCost: 300000);
    await purchases.confirmPurchase(p2, paymentLines: [const PaymentLineInput(method: 'CASH', amount: 300000)]);

    // Un cliente le paga 200.000 directo al proveedor: no sale de nuestra caja.
    await shop.sale(sofa, price: 200000, lines: [
      PaymentLineInput(method: 'SUPPLIER', amount: 200000, supplierId: supplierId),
    ]);

    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(shop.db)]);
    addTearDown(container.dispose);
    final entries = await container.read(auditEntriesProvider.future);
    final totals = auditTotals(entries);

    expect(totals.outflow, 1000000 + 300000, reason: 'antes sumaba 2.500.000');
    expect(totals.committed, 1000000 + 300000);
    expect(entries.where((e) => e.category == AuditCategory.supplierPayment).length, 2);
    expect(entries.where((e) => e.category == AuditCategory.purchase).length, 2);
  });
}
