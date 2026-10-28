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
  const PaymentLineInput({
    required this.method,
    required this.amount,
    this.accountId,
    this.supplierId,
  });
  final String method; // 'CASH' | 'CONSIGNMENT' | 'SUPPLIER'
  final int amount;
  final int? accountId;

  /// Proveedor al que se le mandó la plata directamente, cuando method es
  /// 'SUPPLIER'.
  final int? supplierId;
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

      // Consume lotes FIFO por cada ítem. No bloquea por falta de stock:
      // casi todos los días entra mercancía nueva, así que se puede vender
      // algo que ya estaba apartado (se repone al día siguiente); el
      // inventario puede quedar en negativo mientras tanto, señal de que
      // hay que conseguir más.
      for (final it in items) {
        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(sale.warehouseId)))
            .getSingleOrNull();

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
                supplierId: Value(line.supplierId),
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

        await creditSupplierIfDirectPayment(
          _db,
          line,
          detail: 'Pago directo desde venta ${sale.number}',
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

        var consumedQty = 0;
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
          consumedQty += c.quantity;
        }

        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(sale.warehouseId)))
            .getSingleOrNull();
        if (stock != null) {
          // Lo que ya se había descontado físicamente (consumptions) vuelve
          // al físico; lo que seguía apenas reservado (venta generada por un
          // apartado que nunca se marcó como entregado) libera la reserva
          // en vez de sumarse dos veces al físico.
          final notYetConsumed = it.quantity - consumedQty;
          final newReserved = stock.reservedQuantity - notYetConsumed;
          await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
            StockCompanion(
              quantity: Value(stock.quantity + consumedQty),
              reservedQuantity: Value(newReserved < 0 ? 0 : newReserved),
            ),
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

      // Si la venta salió de facturar un apartado, el apartado también
      // queda devuelto: así nunca se puede marcar "Entregado" y descontar
      // inventario de una venta que ya se devolvió.
      await (_db.update(_db.layaways)..where((l) => l.saleId.equals(saleId)))
          .write(const LayawaysCompanion(state: Value('RETURNED')));
    });
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(databaseProvider));
});

/// Si la línea de pago fue directo a un proveedor (el cliente le manda la
/// plata a, por ejemplo, un proveedor para cubrir el pedido, sin que pase
/// por la caja ni una cuenta propia del negocio), eso también abona la
/// deuda con ese proveedor — compartido entre Ventas y Apartados porque
/// ambos permiten esta forma de pago.
Future<void> creditSupplierIfDirectPayment(
  AppDatabase db,
  PaymentLineInput line, {
  required String detail,
}) async {
  if (line.method != 'SUPPLIER' || line.supplierId == null) return;
  await db.into(db.supplierPayments).insert(
        SupplierPaymentsCompanion.insert(
          supplierId: line.supplierId!,
          amount: line.amount,
          note: Value(detail),
        ),
      );
  await db.into(db.cashMovements).insert(
        CashMovementsCompanion.insert(
          type: 'SUPPLIER_PAYMENT',
          amount: -line.amount,
          method: const Value('SUPPLIER'),
          detail: Value(detail),
          refType: 'SUPPLIER',
          refId: line.supplierId!,
        ),
      );
}
