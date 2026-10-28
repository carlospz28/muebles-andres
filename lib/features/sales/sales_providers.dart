import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/widgets/errors.dart';

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

/// Una línea de un kit ya repartida (precio y descuento de cada componente).
class KitLine {
  const KitLine({required this.productId, required this.quantity, required this.unitPrice, this.discount = 0});
  final int productId;
  final int quantity;
  final int unitPrice;
  final int discount;
  int get total => quantity * unitPrice - discount;
}

/// Un kit no puede quedar gratis ni con líneas inválidas.
void checkKitLines(List<KitLine> lines) {
  if (lines.isEmpty) throw StateError('El kit no tiene componentes seleccionados.');
  for (final l in lines) {
    checkLine(quantity: l.quantity, unitPrice: l.unitPrice, discount: l.discount);
  }
  if (lines.fold<int>(0, (a, l) => a + l.total) <= 0) {
    throw StateError('El precio final del kit debe ser mayor que cero.');
  }
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
    checkLine(quantity: quantity, unitPrice: unitPrice, discount: discount);
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

  /// Agrega todas las líneas de un kit. El kit debe quedar con precio
  /// final mayor que cero.
  Future<void> addKitLines({required int saleId, required int kitId, required List<KitLine> lines}) async {
    checkKitLines(lines);
    for (final l in lines) {
      await addItem(
        saleId: saleId,
        productId: l.productId,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        discount: l.discount,
        kitId: kitId,
      );
    }
  }

  Future<void> removeItem(int itemId, int saleId) async {
    await (_db.delete(_db.saleItems)..where((i) => i.id.equals(itemId))).go();
    await _recalcTotals(saleId);
  }

  Future<void> setCommissionRate(int saleId, double rate) async {
    checkRate(rate);
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

  /// Confirma la venta: consume los lotes FIFO más antiguos primero (para
  /// que el costo real de la venta sea el del lote que corresponde),
  /// descuenta stock físico, registra el pago (posiblemente mixto: parte
  /// efectivo + parte consignación) y abona la caja. Devuelve los avisos de
  /// unidades vendidas sin inventario registrado (vacío si todo alcanzó).
  Future<List<UncostedUnits>> confirmSale({
    required int saleId,
    required List<PaymentLineInput> paymentLines,
  }) async {
    final warnings = <UncostedUnits>[];
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
      // hay que conseguir más (y se avisa en pantalla).
      for (final it in items) {
        final w = await consumeItemFifo(
          _db,
          item: it,
          warehouseId: sale.warehouseId,
          refType: 'SALE',
          refId: saleId,
          note: 'Venta ${sale.number}',
          releaseReservation: false,
        );
        if (w != null) warnings.add(w);
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
    return warnings;
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

      // ¿La mercancía salió físicamente? Sí, salvo que la venta venga de un
      // apartado que todavía no se había entregado (seguía solo reservada).
      final sourceLayaway = await (_db.select(_db.layaways)..where((l) => l.saleId.equals(saleId)))
          .getSingleOrNull();
      final wentOut = sourceLayaway == null || sourceLayaway.delivered;

      for (final it in items) {
        final consumptions = await (_db.select(_db.saleItemLotConsumptions)
              ..where((c) => c.saleItemId.equals(it.id)))
            .get();

        var consumedQty = 0;
        var consumedCost = 0;
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
          consumedCost += c.quantity * c.unitCost;
        }

        // Unidades que se vendieron sin lote (#4): si salieron, vuelven
        // como un lote nuevo con el mismo costo con que se costearon.
        final withoutLot = it.quantity - consumedQty;
        if (wentOut && withoutLot > 0) {
          final unitCost = ((it.costTotal - consumedCost) / withoutLot).round();
          final lotId = await _db.into(_db.productLots).insert(
                ProductLotsCompanion.insert(
                  productId: it.productId,
                  warehouseId: sale.warehouseId,
                  quantityReceived: withoutLot,
                  quantityRemaining: withoutLot,
                  unitCost: unitCost < 0 ? 0 : unitCost,
                ),
              );
          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: it.productId,
                  warehouseId: sale.warehouseId,
                  type: 'IN',
                  quantity: withoutLot,
                  lotId: Value(lotId),
                  refType: 'SALE_RETURN',
                  refId: saleId,
                  note: Value('Devolución venta ${sale.number} (unidades vendidas sin lote)'),
                ),
              );
        }

        final stock = await (_db.select(_db.stock)
              ..where((s) =>
                  s.productId.equals(it.productId) &
                  s.warehouseId.equals(sale.warehouseId)))
            .getSingleOrNull();
        if (stock != null) {
          // Si la mercancía salió, todo vuelve al físico. Si seguía apenas
          // reservada (apartado facturado sin entregar), se libera la reserva
          // en vez de sumarse dos veces al físico.
          final newReserved = stock.reservedQuantity - it.quantity;
          await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
            wentOut
                ? StockCompanion(quantity: Value(stock.quantity + it.quantity))
                : StockCompanion(reservedQuantity: Value(newReserved < 0 ? 0 : newReserved)),
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

      // La plata se devuelve por las mismas formas de pago con que entró:
      // los abonos del apartado si la venta salió de uno, o los pagos de la
      // venta directa.
      final fromLayaway = sourceLayaway;
      final originalPayments = await (_db.select(_db.payments)
            ..where((p) => fromLayaway != null
                ? p.layawayId.equals(fromLayaway.id)
                : p.saleId.equals(saleId)))
          .get();
      await refundPaymentLines(
        _db,
        payments: originalPayments,
        saleId: fromLayaway == null ? saleId : null,
        layawayId: fromLayaway?.id,
        fallbackAmount: sale.total,
        type: 'SALE_REFUND',
        refType: 'SALE_RETURN',
        refId: saleId,
        detail: 'Devolución venta ${sale.number}: $reason',
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

/// Unidades que salieron sin lote de inventario que las respaldara.
class UncostedUnits {
  const UncostedUnits({required this.productName, required this.units, required this.unitCost});
  final String productName;
  final int units;

  /// Último costo conocido con el que se costearon, o null si el producto
  /// nunca ha tenido un ingreso de inventario (quedan a costo 0).
  final int? unitCost;

  String get message => unitCost == null
      ? '$productName: $units unidad(es) sin inventario y sin costo conocido — '
          'quedaron a costo \$0 (la utilidad se verá más alta). Registra su ingreso.'
      : '$productName: $units unidad(es) sin inventario registrado — se costearon '
          'con el último costo conocido (\$$unitCost c/u). Registra la compra o el ingreso.';
}

/// Saca del inventario las unidades de [item] (dentro de una transacción):
/// consume los lotes FIFO del más antiguo al más nuevo, deja su rastro
/// (consumos y movimientos) y guarda en el ítem su costo real. Las unidades
/// que no alcancen a cubrirse con lotes se costean con el último costo
/// conocido del producto y se devuelven como aviso. Descuenta la
/// existencia física (creando la fila de Stock si no existía, aunque quede
/// en negativo) y, si [releaseReservation], también la reserva.
Future<UncostedUnits?> consumeItemFifo(
  AppDatabase db, {
  required SaleItem item,
  required int warehouseId,
  required String refType,
  required int refId,
  required String note,
  required bool releaseReservation,
}) async {
  var remaining = item.quantity;
  var costTotal = 0;

  final lots = await (db.select(db.productLots)
        ..where((l) =>
            l.productId.equals(item.productId) &
            l.warehouseId.equals(warehouseId) &
            l.quantityRemaining.isBiggerThanValue(0))
        ..orderBy([(l) => OrderingTerm.asc(l.receivedAt), (l) => OrderingTerm.asc(l.id)]))
      .get();

  for (final lot in lots) {
    if (remaining <= 0) break;
    final take = remaining < lot.quantityRemaining ? remaining : lot.quantityRemaining;
    await (db.update(db.productLots)..where((l) => l.id.equals(lot.id)))
        .write(ProductLotsCompanion(quantityRemaining: Value(lot.quantityRemaining - take)));
    await db.into(db.saleItemLotConsumptions).insert(
          SaleItemLotConsumptionsCompanion.insert(
            saleItemId: item.id,
            lotId: lot.id,
            quantity: take,
            unitCost: lot.unitCost,
          ),
        );
    await db.into(db.stockMovements).insert(
          StockMovementsCompanion.insert(
            productId: item.productId,
            warehouseId: warehouseId,
            type: 'OUT',
            quantity: take,
            lotId: Value(lot.id),
            refType: refType,
            refId: refId,
            note: Value(note),
          ),
        );
    costTotal += take * lot.unitCost;
    remaining -= take;
  }

  UncostedUnits? warning;
  if (remaining > 0) {
    // Sin lotes suficientes: último costo conocido (el lote más reciente
    // que haya tenido el producto, aunque ya esté agotado).
    final lastLot = await (db.select(db.productLots)
          ..where((l) => l.productId.equals(item.productId))
          ..orderBy([(l) => OrderingTerm.desc(l.receivedAt), (l) => OrderingTerm.desc(l.id)])
          ..limit(1))
        .getSingleOrNull();
    costTotal += remaining * (lastLot?.unitCost ?? 0);
    await db.into(db.stockMovements).insert(
          StockMovementsCompanion.insert(
            productId: item.productId,
            warehouseId: warehouseId,
            type: 'OUT',
            quantity: remaining,
            refType: refType,
            refId: refId,
            note: Value('$note (sin lote: costo ${lastLot == null ? 'desconocido' : 'último conocido'})'),
          ),
        );
    final product =
        await (db.select(db.products)..where((p) => p.id.equals(item.productId))).getSingle();
    warning = UncostedUnits(productName: product.name, units: remaining, unitCost: lastLot?.unitCost);
  }

  await (db.update(db.saleItems)..where((i) => i.id.equals(item.id)))
      .write(SaleItemsCompanion(costTotal: Value(costTotal)));

  final stock = await (db.select(db.stock)
        ..where((s) => s.productId.equals(item.productId) & s.warehouseId.equals(warehouseId)))
      .getSingleOrNull();
  if (stock == null) {
    await db.into(db.stock).insert(
          StockCompanion.insert(
            productId: item.productId,
            warehouseId: warehouseId,
            quantity: Value(-item.quantity),
          ),
        );
  } else {
    final newReserved = stock.reservedQuantity - item.quantity;
    await (db.update(db.stock)..where((s) => s.id.equals(stock.id))).write(
      StockCompanion(
        quantity: Value(stock.quantity - item.quantity),
        reservedQuantity: releaseReservation
            ? Value(newReserved < 0 ? 0 : newReserved)
            : const Value.absent(),
      ),
    );
  }
  return warning;
}

/// Devuelve la plata de [payments] por las MISMAS formas de pago con que
/// entró, línea por línea (debe llamarse dentro de una transacción):
/// - deja un pago de "Devolución" con líneas negativas (mismo método y
///   cuenta), así el saldo de cada cuenta de consignación baja lo que
///   corresponde;
/// - escribe una fila [type] en el libro por cada línea, con su método;
/// - si la línea fue directo a un proveedor, revierte también ese abono
///   (la deuda con el proveedor vuelve a subir; no toca caja ni banco).
/// Si no hay líneas de pago (ventas muy viejas), devuelve [fallbackAmount]
/// en efectivo como antes.
Future<void> refundPaymentLines(
  AppDatabase db, {
  required List<Payment> payments,
  int? saleId,
  int? layawayId,
  required int fallbackAmount,
  required String type,
  required String refType,
  required int refId,
  required String detail,
}) async {
  final paymentIds = [for (final p in payments) if (p.totalAmount > 0) p.id];
  final lines = paymentIds.isEmpty
      ? <PaymentLine>[]
      : await (db.select(db.paymentLines)
            ..where((l) => l.paymentId.isIn(paymentIds) & l.amount.isBiggerThanValue(0)))
          .get();

  if (lines.isEmpty) {
    await db.into(db.cashMovements).insert(
          CashMovementsCompanion.insert(
            type: type,
            amount: -fallbackAmount,
            detail: Value(detail),
            refType: refType,
            refId: refId,
          ),
        );
    return;
  }

  final total = lines.fold<int>(0, (a, l) => a + l.amount);
  final refundPaymentId = await db.into(db.payments).insert(
        PaymentsCompanion.insert(
          saleId: Value(saleId),
          layawayId: Value(layawayId),
          totalAmount: Value(-total),
          note: Value(detail),
        ),
      );

  for (final line in lines) {
    await db.into(db.paymentLines).insert(
          PaymentLinesCompanion.insert(
            paymentId: refundPaymentId,
            method: line.method,
            amount: -line.amount,
            accountId: Value(line.accountId),
            supplierId: Value(line.supplierId),
          ),
        );
    await db.into(db.cashMovements).insert(
          CashMovementsCompanion.insert(
            type: type,
            amount: -line.amount,
            method: Value(line.method),
            detail: Value(detail),
            refType: refType,
            refId: refId,
          ),
        );
    if (line.method == 'SUPPLIER' && line.supplierId != null) {
      await db.into(db.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              supplierId: line.supplierId!,
              amount: -line.amount,
              note: Value('Reverso por devolución · $detail'),
            ),
          );
      await db.into(db.cashMovements).insert(
            CashMovementsCompanion.insert(
              type: 'SUPPLIER_PAYMENT',
              amount: line.amount,
              method: const Value('SUPPLIER'),
              detail: Value('Reverso por devolución · $detail'),
              refType: 'SUPPLIER',
              refId: line.supplierId!,
            ),
          );
    }
  }
}

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
