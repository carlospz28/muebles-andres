import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../sales/sales_providers.dart' show PaymentLineInput;

class SupplierBalance {
  const SupplierBalance(this.supplier, this.totalPurchased, this.totalPaid);
  final Supplier supplier;
  final int totalPurchased;
  final int totalPaid;

  /// Incluye la deuda inicial cargada al crear/editar el proveedor (para
  /// proveedores a los que ya se les debía algo antes de usar la app).
  int get balance => supplier.openingBalance + totalPurchased - totalPaid;
}

/// Cuenta por proveedor: cuánto se le ha comprado (confirmado) contra
/// cuánto se le ha pagado — la deuda pendiente, para saber cuánto se le
/// debe y de dónde salió cada pago (efectivo o consignación).
final supplierBalancesProvider = StreamProvider.autoDispose<List<SupplierBalance>>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.suppliers).watch().map((_) {}),
    db.select(db.purchases).watch().map((_) {}),
    db.select(db.supplierPayments).watch().map((_) {}),
  ]);

  Future<List<SupplierBalance>> load() async {
    final suppliers = await db.select(db.suppliers).get();

    // Lo pagado al confirmar cada compra (Purchases.paidAmount) es la
    // fuente de verdad ahí — incluye tanto las compras de contado nuevas
    // como las compras viejas de antes de este cambio, que siempre se
    // marcaban pagadas de una. Aparte se suman los abonos sueltos hechos
    // desde "Pagar" en Proveedores (no ligados a una compra puntual).
    final purchaseRows =
        await (db.select(db.purchases)..where((p) => p.state.equals('CONFIRMED'))).get();
    final purchasedBySupplier = <int, int>{};
    final paidAtConfirmBySupplier = <int, int>{};
    for (final p in purchaseRows) {
      purchasedBySupplier[p.supplierId] = (purchasedBySupplier[p.supplierId] ?? 0) + p.total;
      paidAtConfirmBySupplier[p.supplierId] =
          (paidAtConfirmBySupplier[p.supplierId] ?? 0) + p.paidAmount;
    }

    final standaloneRows = await (db.select(db.supplierPayments)
          ..where((sp) => sp.purchaseId.isNull()))
        .get();
    final standalonePaidBySupplier = <int, int>{};
    for (final p in standaloneRows) {
      standalonePaidBySupplier[p.supplierId] =
          (standalonePaidBySupplier[p.supplierId] ?? 0) + p.amount;
    }

    return [
      for (final s in suppliers)
        SupplierBalance(
          s,
          purchasedBySupplier[s.id] ?? 0,
          (paidAtConfirmBySupplier[s.id] ?? 0) + (standalonePaidBySupplier[s.id] ?? 0),
        ),
    ];
  }

  return trigger.asyncMap((_) => load());
});

final purchasesStreamProvider = StreamProvider.autoDispose<List<Purchase>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.purchases)..orderBy([(p) => OrderingTerm.desc(p.date)]))
      .watch();
});

/// Lo que se le debe hoy a un proveedor (misma regla de
/// [supplierBalancesProvider]): deuda inicial + compras confirmadas − lo
/// pagado al confirmarlas − abonos sueltos (incluye pagos directos de
/// clientes y sus reversos).
Future<int> supplierDebt(AppDatabase db, int supplierId) async {
  final supplier = await (db.select(db.suppliers)..where((s) => s.id.equals(supplierId))).getSingle();
  final purchases = await (db.select(db.purchases)
        ..where((p) => p.supplierId.equals(supplierId) & p.state.equals('CONFIRMED')))
      .get();
  final standalone = await (db.select(db.supplierPayments)
        ..where((p) => p.supplierId.equals(supplierId) & p.purchaseId.isNull()))
      .get();
  return supplier.openingBalance +
      purchases.fold<int>(0, (a, p) => a + p.total - p.paidAmount) -
      standalone.fold<int>(0, (a, p) => a + p.amount);
}

class PurchaseListItem {
  PurchaseListItem(this.purchase, this.supplierName);
  final Purchase purchase;
  final String supplierName;
}

final purchasesWithSupplierProvider =
    StreamProvider.autoDispose<List<PurchaseListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.purchases).join([
    innerJoin(db.suppliers, db.suppliers.id.equalsExp(db.purchases.supplierId)),
  ])
    ..orderBy([OrderingTerm.desc(db.purchases.date)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => PurchaseListItem(
              row.readTable(db.purchases),
              row.readTable(db.suppliers).name,
            ))
        .toList();
  });
});

class PurchaseItemView {
  PurchaseItemView(this.item, this.productName);
  final PurchaseItem item;
  final String productName;
}

final purchaseByIdProvider =
    StreamProvider.autoDispose.family<Purchase, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.purchases)..where((p) => p.id.equals(id))).watchSingle();
});

final purchaseItemsProvider =
    StreamProvider.autoDispose.family<List<PurchaseItemView>, int>((ref, purchaseId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.purchaseItems).join([
    innerJoin(db.products, db.products.id.equalsExp(db.purchaseItems.productId)),
  ])
    ..where(db.purchaseItems.purchaseId.equals(purchaseId));

  return query.watch().map((rows) {
    return rows
        .map((row) => PurchaseItemView(
              row.readTable(db.purchaseItems),
              row.readTable(db.products).name,
            ))
        .toList();
  });
});

class PurchasesRepository {
  PurchasesRepository(this._db);
  final AppDatabase _db;

  Future<String> _nextNumber() async {
    final all = await _db.select(_db.purchases).get();
    var maxNumber = 0;
    for (final p in all) {
      final n = int.tryParse(p.number);
      if (n != null && n > maxNumber) maxNumber = n;
    }
    return (maxNumber + 1).toString().padLeft(4, '0');
  }

  Future<int> createDraft({required int supplierId, required int warehouseId}) async {
    final number = await _nextNumber();
    return _db.into(_db.purchases).insert(
          PurchasesCompanion.insert(
            number: number,
            supplierId: supplierId,
            warehouseId: warehouseId,
          ),
        );
  }

  Future<void> addItem({
    required int purchaseId,
    required int productId,
    required int quantity,
    required int unitCost,
  }) async {
    await _db.into(_db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            quantity: quantity,
            unitCost: unitCost,
            lineTotal: Value(quantity * unitCost),
          ),
        );
  }

  Future<void> removeItem(int itemId) async {
    await (_db.delete(_db.purchaseItems)..where((i) => i.id.equals(itemId))).go();
  }

  /// Confirma la compra: crea un lote (ProductLot) por cada ítem con su
  /// propio costo — así, cuando el lote anterior se agote, la siguiente
  /// venta toma automáticamente el costo de este lote nuevo (FIFO),
  /// tal como pidió el cliente ("que se acaben esos productos y cuando
  /// entre un nuevo lote que tenga el nuevo precio").
  ///
  /// Si [paymentLines] viene vacío, la compra queda "a crédito" (no sale
  /// nada de caja todavía, queda como deuda con el proveedor). Si viene
  /// con líneas, deben sumar exactamente el total de la compra.
  Future<void> confirmPurchase(
    int purchaseId, {
    List<PaymentLineInput> paymentLines = const [],
  }) async {
    await _db.transaction(() async {
      final purchase =
          await (_db.select(_db.purchases)..where((p) => p.id.equals(purchaseId)))
              .getSingle();

      if (purchase.state != 'DRAFT') {
        throw StateError('Solo se pueden confirmar compras en borrador.');
      }

      final items = await (_db.select(_db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .get();

      if (items.isEmpty) {
        throw StateError('La compra no tiene productos.');
      }

      var total = 0;
      for (final it in items) {
        total += it.quantity * it.unitCost;

        final lotId = await _db.into(_db.productLots).insert(
              ProductLotsCompanion.insert(
                productId: it.productId,
                warehouseId: purchase.warehouseId,
                purchaseId: Value(purchaseId),
                quantityReceived: it.quantity,
                quantityRemaining: it.quantity,
                unitCost: it.unitCost,
              ),
            );

        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(purchase.warehouseId)))
            .getSingleOrNull();

        if (stock == null) {
          await _db.into(_db.stock).insert(
                StockCompanion.insert(
                  productId: it.productId,
                  warehouseId: purchase.warehouseId,
                  quantity: Value(it.quantity),
                ),
              );
        } else {
          await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
            StockCompanion(quantity: Value(stock.quantity + it.quantity)),
          );
        }

        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: it.productId,
                warehouseId: purchase.warehouseId,
                type: 'IN',
                quantity: it.quantity,
                lotId: Value(lotId),
                refType: 'PURCHASE',
                refId: purchaseId,
                note: Value('Compra ${purchase.number}'),
              ),
            );
      }

      final paidNow = paymentLines.fold<int>(0, (sum, l) => sum + l.amount);
      if (paidNow > 0 && paidNow != total) {
        throw StateError(
          'El pago (\$$paidNow) no coincide con el total de la compra (\$$total).',
        );
      }

      await (_db.update(_db.purchases)..where((p) => p.id.equals(purchaseId))).write(
        PurchasesCompanion(
          state: const Value('CONFIRMED'),
          subtotal: Value(total),
          total: Value(total),
          paidAmount: Value(paidNow),
          paymentType: Value(paidNow > 0 ? 'CASH' : 'CREDIT'),
        ),
      );

      for (final line in paymentLines) {
        await _db.into(_db.supplierPayments).insert(
              SupplierPaymentsCompanion.insert(
                supplierId: purchase.supplierId,
                purchaseId: Value(purchaseId),
                amount: line.amount,
                method: Value(line.method),
                accountId: Value(line.accountId),
              ),
            );
        await _db.into(_db.cashMovements).insert(
              CashMovementsCompanion.insert(
                type: 'SUPPLIER_PAYMENT',
                amount: -line.amount,
                method: Value(line.method),
                detail: Value('Compra ${purchase.number}'),
                refType: 'SUPPLIER',
                refId: purchase.supplierId,
              ),
            );
      }
    });
  }

  /// Abono a proveedor no ligado a una compra puntual (ej. "le pagué
  /// $200.000 a cuenta de lo que le debo en general").
  Future<void> paySupplier({
    required int supplierId,
    required List<PaymentLineInput> paymentLines,
  }) async {
    if (paymentLines.isEmpty || paymentLines.any((l) => l.amount <= 0)) {
      throw StateError('Cada pago debe ser mayor que cero.');
    }
    await _db.transaction(() async {
      final debt = await supplierDebt(_db, supplierId);
      final total = paymentLines.fold<int>(0, (a, l) => a + l.amount);
      if (total > debt) {
        throw StateError('No se puede abonar más de lo que se le debe al proveedor (\$$debt).');
      }
      for (final line in paymentLines) {
        await _db.into(_db.supplierPayments).insert(
              SupplierPaymentsCompanion.insert(
                supplierId: supplierId,
                amount: line.amount,
                method: Value(line.method),
                accountId: Value(line.accountId),
              ),
            );
        await _db.into(_db.cashMovements).insert(
              CashMovementsCompanion.insert(
                type: 'SUPPLIER_PAYMENT',
                amount: -line.amount,
                method: Value(line.method),
                detail: const Value('Abono a proveedor'),
                refType: 'SUPPLIER',
                refId: supplierId,
              ),
            );
      }
    });
  }
}

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository(ref.watch(databaseProvider));
});
