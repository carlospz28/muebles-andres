import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

final salesStreamProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.sales)..orderBy([(s) => OrderingTerm.desc(s.date)]))
      .watch();
});

class SaleListItem {
  SaleListItem(this.sale, this.customerName);
  final Sale sale;
  final String customerName;
}

final salesWithCustomerProvider = StreamProvider.autoDispose<List<SaleListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sales).join([
    innerJoin(db.customers, db.customers.id.equalsExp(db.sales.customerId)),
  ])
    ..orderBy([OrderingTerm.desc(db.sales.date)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => SaleListItem(
              row.readTable(db.sales),
              row.readTable(db.customers).name,
            ))
        .toList();
  });
});

final saleByIdProvider = StreamProvider.autoDispose.family<Sale, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.sales)..where((s) => s.id.equals(id))).watchSingle();
});

class SaleItemView {
  SaleItemView(this.item, this.productName);
  final SaleItem item;
  final String productName;
}

final saleItemsProvider =
    StreamProvider.autoDispose.family<List<SaleItemView>, int>((ref, saleId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.saleItems).join([
    innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
  ])
    ..where(db.saleItems.saleId.equals(saleId));

  return query.watch().map((rows) {
    return rows
        .map((row) => SaleItemView(
              row.readTable(db.saleItems),
              row.readTable(db.products).name,
            ))
        .toList();
  });
});

class PaymentLineInput {
  const PaymentLineInput({required this.method, required this.amount, this.accountId});
  final String method; // 'CASH' | 'CONSIGNMENT'
  final int amount;
  final int? accountId;
}

class SalesRepository {
  SalesRepository(this._db);
  final AppDatabase _db;

  Future<String> _nextNumber() async {
    final all = await _db.select(_db.sales).get();
    var maxNumber = 0;
    for (final s in all) {
      final n = int.tryParse(s.number);
      if (n != null && n > maxNumber) maxNumber = n;
    }
    return (maxNumber + 1).toString().padLeft(4, '0');
  }

  Future<int> createDraft({
    required int customerId,
    required int warehouseId,
    int? employeeId,
  }) async {
    final number = await _nextNumber();
    return _db.into(_db.sales).insert(
          SalesCompanion.insert(
            number: number,
            customerId: customerId,
            warehouseId: warehouseId,
            employeeId: Value(employeeId),
          ),
        );
  }

  Future<void> _recalcTotals(int saleId) async {
    final sale =
        await (_db.select(_db.sales)..where((s) => s.id.equals(saleId))).getSingle();
    final items =
        await (_db.select(_db.saleItems)..where((i) => i.saleId.equals(saleId))).get();

    var subtotal = 0;
    var discountTotal = 0;
    for (final it in items) {
      subtotal += it.quantity * it.unitPrice;
      discountTotal += it.discount;
    }
    final total = subtotal - discountTotal;
    final rate = sale.commissionRate;
    final commissionAmount = (total * rate / 100).round();

    await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
      SalesCompanion(
        subtotal: Value(subtotal),
        discountTotal: Value(discountTotal),
        total: Value(total),
        commissionAmount: Value(commissionAmount),
      ),
    );
  }

  Future<void> addItem({
    required int saleId,
    required int productId,
    required int quantity,
    required int unitPrice,
    int discount = 0,
    int? kitId,
  }) async {
    await _db.into(_db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            kitId: Value(kitId),
            quantity: quantity,
            unitPrice: unitPrice,
            discount: Value(discount),
            lineTotal: Value(quantity * unitPrice - discount),
          ),
        );
    await _recalcTotals(saleId);
  }

  Future<void> removeItem(int itemId, int saleId) async {
    await (_db.delete(_db.saleItems)..where((i) => i.id.equals(itemId))).go();
    await _recalcTotals(saleId);
  }

  Future<void> setCommissionRate(int saleId, double rate) async {
    await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
        .write(SalesCompanion(commissionRate: Value(rate)));
    await _recalcTotals(saleId);
  }

  Future<void> setDelivered(int saleId, bool delivered) async {
    await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
      SalesCompanion(
        delivered: Value(delivered),
        deliveredAt: Value(delivered ? DateTime.now() : null),
      ),
    );
  }

  /// Confirma la venta: valida stock, consume los lotes FIFO más antiguos
  /// primero (para que el costo real de la venta sea el del lote que
  /// corresponde), descuenta stock físico, registra el pago (posiblemente
  /// mixto: parte efectivo + parte consignación) y abona la caja.
  Future<void> confirmSale({
    required int saleId,
    required List<PaymentLineInput> paymentLines,
  }) async {
    await _db.transaction(() async {
      await _recalcTotals(saleId);
      final sale =
          await (_db.select(_db.sales)..where((s) => s.id.equals(saleId))).getSingle();

      if (sale.state != 'DRAFT') {
        throw StateError('Solo se pueden confirmar ventas en borrador.');
      }

      final items =
          await (_db.select(_db.saleItems)..where((i) => i.saleId.equals(saleId))).get();
      if (items.isEmpty) {
        throw StateError('La venta no tiene productos.');
      }

      final paidTotal = paymentLines.fold<int>(0, (sum, l) => sum + l.amount);
      if (paidTotal != sale.total) {
        throw StateError(
          'El pago (\$$paidTotal) no coincide con el total de la venta (\$${sale.total}).',
        );
      }

      // Validar disponibilidad y consumir lotes FIFO por cada ítem.
      for (final it in items) {
        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(sale.warehouseId)))
            .getSingleOrNull();

        final available = (stock?.quantity ?? 0) - (stock?.reservedQuantity ?? 0);
        if (available < it.quantity) {
          throw StateError(
            'Stock insuficiente para el producto (disponible: $available, requerido: ${it.quantity}).',
          );
        }

        var remainingToConsume = it.quantity;
        var costTotal = 0;

        final lots = await (_db.select(_db.productLots)
              ..where((l) =>
                  l.productId.equals(it.productId) &
                  l.warehouseId.equals(sale.warehouseId) &
                  l.quantityRemaining.isBiggerThanValue(0))
              ..orderBy([(l) => OrderingTerm.asc(l.receivedAt)]))
            .get();

        for (final lot in lots) {
          if (remainingToConsume <= 0) break;
          final takeFromLot = remainingToConsume < lot.quantityRemaining
              ? remainingToConsume
              : lot.quantityRemaining;
          if (takeFromLot <= 0) continue;

          await (_db.update(_db.productLots)..where((l) => l.id.equals(lot.id))).write(
            ProductLotsCompanion(
              quantityRemaining: Value(lot.quantityRemaining - takeFromLot),
            ),
          );

          await _db.into(_db.saleItemLotConsumptions).insert(
                SaleItemLotConsumptionsCompanion.insert(
                  saleItemId: it.id,
                  lotId: lot.id,
                  quantity: takeFromLot,
                  unitCost: lot.unitCost,
                ),
              );

          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: it.productId,
                  warehouseId: sale.warehouseId,
                  type: 'OUT',
                  quantity: takeFromLot,
                  lotId: Value(lot.id),
                  refType: 'SALE',
                  refId: saleId,
                  note: Value('Venta ${sale.number}'),
                ),
              );

          costTotal += takeFromLot * lot.unitCost;
          remainingToConsume -= takeFromLot;
        }

        await (_db.update(_db.saleItems)..where((i) => i.id.equals(it.id)))
            .write(SaleItemsCompanion(costTotal: Value(costTotal)));

        if (stock != null) {
          await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
            StockCompanion(quantity: Value(stock.quantity - it.quantity)),
          );
        }
      }

      await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
          .write(const SalesCompanion(state: Value('CONFIRMED')));

      final paymentId = await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              saleId: Value(saleId),
              totalAmount: Value(paidTotal),
            ),
          );

      for (final line in paymentLines) {
        await _db.into(_db.paymentLines).insert(
              PaymentLinesCompanion.insert(
                paymentId: paymentId,
                method: line.method,
                amount: line.amount,
                accountId: Value(line.accountId),
              ),
            );

        await _db.into(_db.cashMovements).insert(
              CashMovementsCompanion.insert(
                type: 'SALE',
                amount: line.amount,
                method: Value(line.method),
                detail: Value('Venta ${sale.number}'),
                refType: 'SALE',
                refId: saleId,
              ),
            );
      }
    });
  }

  /// Devolución de venta: revierte exactamente los lotes de donde salió
  /// la mercancía, sube el stock físico y descuenta la caja.
  Future<void> confirmReturn({
    required int saleId,
    required String reason,
  }) async {
    await _db.transaction(() async {
      final sale =
          await (_db.select(_db.sales)..where((s) => s.id.equals(saleId))).getSingle();

      if (sale.state != 'CONFIRMED') {
        throw StateError('Solo se pueden devolver ventas confirmadas.');
      }
      if (sale.isReturn) {
        throw StateError('Esta venta ya fue devuelta.');
      }

      final items =
          await (_db.select(_db.saleItems)..where((i) => i.saleId.equals(saleId))).get();

      for (final it in items) {
        final consumptions = await (_db.select(_db.saleItemLotConsumptions)
              ..where((c) => c.saleItemId.equals(it.id)))
            .get();

        for (final c in consumptions) {
          final lot = await (_db.select(_db.productLots)..where((l) => l.id.equals(c.lotId)))
              .getSingleOrNull();
          if (lot != null) {
            await (_db.update(_db.productLots)..where((l) => l.id.equals(lot.id))).write(
              ProductLotsCompanion(
                quantityRemaining: Value(lot.quantityRemaining + c.quantity),
              ),
            );
          }

          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: it.productId,
                  warehouseId: sale.warehouseId,
                  type: 'IN',
                  quantity: c.quantity,
                  lotId: Value(c.lotId),
                  refType: 'SALE_RETURN',
                  refId: saleId,
                  note: Value('Devolución venta ${sale.number}'),
                ),
              );
        }

        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(sale.warehouseId)))
            .getSingleOrNull();
        if (stock != null) {
          await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
            StockCompanion(quantity: Value(stock.quantity + it.quantity)),
          );
        }
      }

      await _db.into(_db.saleReturns).insert(
            SaleReturnsCompanion.insert(
              saleId: saleId,
              reason: Value(reason),
              state: const Value('CONFIRMED'),
              refundAmount: Value(sale.total),
            ),
          );

      await _db.into(_db.cashMovements).insert(
            CashMovementsCompanion.insert(
              type: 'SALE_REFUND',
              amount: -sale.total,
              detail: Value('Devolución venta ${sale.number}: $reason'),
              refType: 'SALE_RETURN',
              refId: saleId,
            ),
          );

      await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
          .write(const SalesCompanion(isReturn: Value(true)));
    });
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(databaseProvider));
});
