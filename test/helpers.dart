import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/features/inventory/catalog_providers.dart';
import 'package:muebles_andres/features/layaways/layaways_providers.dart';
import 'package:muebles_andres/features/sales/sales_providers.dart';

/// Escenario de prueba sobre una base EN MEMORIA, armado con los mismos
/// repositorios que usa la app.
class TestShop {
  TestShop()
      : db = (() {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
          return AppDatabase.forTesting(NativeDatabase.memory());
        })();

  final AppDatabase db;
  late final int warehouseId;
  late final int customerId;
  late final int categoryId;

  SalesRepository get sales => SalesRepository(db);
  LayawaysRepository get layaways => LayawaysRepository(db);
  CatalogRepository get catalog => CatalogRepository(db);

  Future<void> init() async {
    warehouseId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'Principal'));
    customerId = await db.into(db.customers).insert(CustomersCompanion.insert(name: 'Ana'));
    categoryId = await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Salas'));
  }

  Future<void> close() => db.close();

  /// Producto con [stock] unidades ingresadas a [unitCost] (0 = sin lote).
  Future<int> product(String name, {int price = 1000000, int stock = 0, int unitCost = 600000}) async {
    final id = await catalog.saveProduct(name: name, categoryId: categoryId, price: price);
    if (stock > 0) {
      await catalog.addInventoryEntry(
        productId: id,
        warehouseId: warehouseId,
        quantity: stock,
        unitCost: unitCost,
      );
    }
    return id;
  }

  /// Venta confirmada de [qty] unidades de [productId], pagada con [lines]
  /// (por defecto todo en efectivo).
  Future<int> sale(int productId, {int qty = 1, int price = 1000000, List<PaymentLineInput>? lines, int? employeeId, double rate = 0}) async {
    final id = await sales.createDraft(customerId: customerId, warehouseId: warehouseId, employeeId: employeeId);
    await sales.addItem(saleId: id, productId: productId, quantity: qty, unitPrice: price);
    if (rate > 0) await sales.setCommissionRate(id, rate);
    await sales.confirmSale(
      saleId: id,
      paymentLines: lines ?? [PaymentLineInput(method: 'CASH', amount: qty * price)],
    );
    return id;
  }

  /// Apartado de [qty] unidades, abonado completo con [lines] y facturado.
  /// Devuelve (layawayId, saleId).
  Future<(int, int)> invoicedLayaway(int productId, {int qty = 1, int price = 1000000, List<PaymentLineInput>? lines, int? employeeId, double rate = 0}) async {
    final id = await layaways.createDraft(customerId: customerId, warehouseId: warehouseId, employeeId: employeeId);
    await layaways.addItem(layawayId: id, productId: productId, quantity: qty, unitPrice: price);
    await layaways.addPayment(
      layawayId: id,
      paymentLines: lines ?? [PaymentLineInput(method: 'CASH', amount: qty * price)],
      commissionRate: rate,
    );
    final saleId = await layaways.invoiceToSale(id);
    return (id, saleId);
  }

  Future<StockData> stock(int productId) =>
      (db.select(db.stock)..where((s) => s.productId.equals(productId))).getSingle();

  Future<int> lotsRemaining(int productId) async {
    final lots = await (db.select(db.productLots)..where((l) => l.productId.equals(productId))).get();
    return lots.fold<int>(0, (a, l) => a + l.quantityRemaining);
  }

  Future<Layaway> layaway(int id) => (db.select(db.layaways)..where((l) => l.id.equals(id))).getSingle();

  /// Suma del libro mayor (opcionalmente solo una forma de pago).
  Future<int> ledger({String? method, String? type}) async {
    final q = db.selectOnly(db.cashMovements)..addColumns([db.cashMovements.amount.sum()]);
    if (method != null) q.where(db.cashMovements.method.equals(method));
    if (type != null) q.where(db.cashMovements.type.equals(type));
    return (await q.getSingle()).read(db.cashMovements.amount.sum()) ?? 0;
  }
}
