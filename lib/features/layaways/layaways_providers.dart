import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/widgets/errors.dart';
import '../sales/sales_providers.dart'
    show
        KitLine,
        PaymentLineInput,
        UncostedUnits,
        checkKitLines,
        consumeItemFifo,
        creditSupplierIfDirectPayment,
        refundPaymentLines;

final layawaysStreamProvider = StreamProvider.autoDispose<List<Layaway>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.layaways)..orderBy([(l) => OrderingTerm.desc(l.date)]))
      .watch();
});

class LayawayListItem {
  LayawayListItem(this.layaway, this.customerName);
  final Layaway layaway;
  final String customerName;
}

final layawaysWithCustomerProvider =
    StreamProvider.autoDispose<List<LayawayListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.layaways).join([
    innerJoin(db.customers, db.customers.id.equalsExp(db.layaways.customerId)),
  ])
    ..orderBy([OrderingTerm.desc(db.layaways.date)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => LayawayListItem(
              row.readTable(db.layaways),
              row.readTable(db.customers).name,
            ))
        .toList();
  });
});

final layawayByIdProvider =
    StreamProvider.autoDispose.family<Layaway, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.layaways)..where((l) => l.id.equals(id))).watchSingle();
});

class LayawayItemView {
  LayawayItemView(this.item, this.productName);
  final LayawayItem item;
  final String productName;
}

final layawayItemsProvider =
    StreamProvider.autoDispose.family<List<LayawayItemView>, int>((ref, layawayId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.layawayItems).join([
    innerJoin(db.products, db.products.id.equalsExp(db.layawayItems.productId)),
  ])
    ..where(db.layawayItems.layawayId.equals(layawayId));

  return query.watch().map((rows) {
    return rows
        .map((row) => LayawayItemView(
              row.readTable(db.layawayItems),
              row.readTable(db.products).name,
            ))
        .toList();
  });
});

/// Total, pagado y saldo del apartado (equivalentes a las @property del
/// modelo Django original: total, total_paid, balance).
class LayawayTotals {
  const LayawayTotals({required this.total, required this.paid});
  final int total;
  final int paid;
  int get balance => (total - paid) < 0 ? 0 : total - paid;
}

final layawayTotalsProvider =
    StreamProvider.autoDispose.family<LayawayTotals, int>((ref, layawayId) {
  final db = ref.watch(databaseProvider);

  Future<LayawayTotals> load() async {
    final total = await (db.selectOnly(db.layawayItems)
          ..addColumns([db.layawayItems.lineTotal.sum()])
          ..where(db.layawayItems.layawayId.equals(layawayId)))
        .map((row) => row.read(db.layawayItems.lineTotal.sum()) ?? 0)
        .getSingle();
    final paid = await (db.selectOnly(db.payments)
          ..addColumns([db.payments.totalAmount.sum()])
          ..where(db.payments.layawayId.equals(layawayId)))
        .map((row) => row.read(db.payments.totalAmount.sum()) ?? 0)
        .getSingle();
    return LayawayTotals(total: total, paid: paid);
  }

  // Se recalcula si cambian los productos del apartado O sus abonos —
  // antes solo escuchaba los productos y el saldo se quedaba "pegado"
  // después de registrar un abono.
  final trigger = StreamGroup.merge<void>([
    (db.select(db.layawayItems)..where((i) => i.layawayId.equals(layawayId)))
        .watch()
        .map((_) {}),
    (db.select(db.payments)..where((p) => p.layawayId.equals(layawayId)))
        .watch()
        .map((_) {}),
  ]);

  return trigger.asyncMap((_) => load());
});

class LayawayPaymentView {
  LayawayPaymentView(this.payment, this.lines);
  final Payment payment;
  final List<PaymentLine> lines;
}

final layawayPaymentsProvider =
    StreamProvider.autoDispose.family<List<Payment>, int>((ref, layawayId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.payments)
        ..where((p) => p.layawayId.equals(layawayId))
        ..orderBy([(p) => OrderingTerm.desc(p.date)]))
      .watch();
});

class LayawaysRepository {
  LayawaysRepository(this._db);
  final AppDatabase _db;

  Future<int> createDraft({
    required int customerId,
    required int warehouseId,
    int? employeeId,
  }) async {
    return _db.into(_db.layaways).insert(
          LayawaysCompanion.insert(
            customerId: customerId,
            warehouseId: warehouseId,
            employeeId: Value(employeeId),
          ),
        );
  }

  /// Agrega un producto al apartado. A diferencia de una venta directa, un
  /// apartado es una promesa de entrega futura: que no haya suficiente
  /// stock hoy no significa que no se vaya a conseguir antes de entregar,
  /// así que esto NUNCA bloquea — solo reserva lo que hay y devuelve
  /// cuántas unidades faltan por conseguir (0 si alcanza), para que la
  /// pantalla pueda avisar sin impedir el apartado.
  Future<int> addItem({
    required int layawayId,
    required int productId,
    required int quantity,
    required int unitPrice,
    int discount = 0,
    int? kitId,
  }) async {
    final line = KitLine(productId: productId, quantity: quantity, unitPrice: unitPrice, discount: discount);
    checkLine(quantity: quantity, unitPrice: unitPrice, discount: discount);
    return _db.transaction(() async {
      final layaway = await _requireInProcess(layawayId);
      return _insertItem(layaway, kitId, line);
    });
  }

  /// Agrega todas las líneas de un kit en una sola transacción (si una
  /// falla, no queda ninguna ni su reserva). Devuelve cuántas unidades
  /// faltan por conseguir. El kit debe quedar con precio final > 0.
  Future<int> addKitLines({required int layawayId, required int kitId, required List<KitLine> lines}) async {
    checkKitLines(lines);
    return _db.transaction(() async {
      final layaway = await _requireInProcess(layawayId);
      var shortage = 0;
      for (final l in lines) {
        shortage += await _insertItem(layaway, kitId, l);
      }
      return shortage;
    });
  }

  /// Solo un apartado en proceso se puede modificar.
  Future<Layaway> _requireInProcess(int layawayId) async {
    final layaway =
        await (_db.select(_db.layaways)..where((l) => l.id.equals(layawayId))).getSingle();
    if (layaway.state != 'IN_PROCESS') {
      throw StateError('El apartado #$layawayId ya no está en proceso: no se puede modificar.');
    }
    return layaway;
  }

  /// Inserta la línea y reserva su mercancía (sin abrir transacción).
  Future<int> _insertItem(Layaway layaway, int? kitId, KitLine l) async {
    checkLine(quantity: l.quantity, unitPrice: l.unitPrice, discount: l.discount);
    final stock = await (_db.select(_db.stock)
          ..where((s) =>
              s.productId.equals(l.productId) & s.warehouseId.equals(layaway.warehouseId)))
        .getSingleOrNull();
    final available = (stock?.quantity ?? 0) - (stock?.reservedQuantity ?? 0);
    final shortage = l.quantity - available > 0 ? l.quantity - available : 0;

    await _db.into(_db.layawayItems).insert(
          LayawayItemsCompanion.insert(
            layawayId: layaway.id,
            productId: l.productId,
            kitId: Value(kitId),
            quantity: l.quantity,
            unitPrice: l.unitPrice,
            discount: Value(l.discount),
            lineTotal: Value(l.total),
          ),
        );

    if (stock == null) {
      await _db.into(_db.stock).insert(
            StockCompanion.insert(
              productId: l.productId,
              warehouseId: layaway.warehouseId,
              reservedQuantity: Value(l.quantity),
            ),
          );
    } else {
      await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
        StockCompanion(reservedQuantity: Value(stock.reservedQuantity + l.quantity)),
      );
    }
    return shortage;
  }

  /// Quita la línea y libera su reserva, todo o nada.
  Future<void> removeItem(int itemId) async {
    return _db.transaction(() async {
      final item =
          await (_db.select(_db.layawayItems)..where((i) => i.id.equals(itemId))).getSingle();
      final layaway = await _requireInProcess(item.layawayId);

      final stock = await (_db.select(_db.stock)
            ..where((s) =>
                s.productId.equals(item.productId) &
                s.warehouseId.equals(layaway.warehouseId)))
          .getSingleOrNull();
      if (stock != null) {
        final newReserved = stock.reservedQuantity - item.quantity;
        await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
          StockCompanion(reservedQuantity: Value(newReserved < 0 ? 0 : newReserved)),
        );
      }

      await (_db.delete(_db.layawayItems)..where((i) => i.id.equals(itemId))).go();
    });
  }

  /// Registra un abono. La comisión de un apartado se calcula sobre cada
  /// abono (no sobre el total), tal como pidió el cliente.
  Future<void> addPayment({
    required int layawayId,
    required List<PaymentLineInput> paymentLines,
    double commissionRate = 0,
  }) async {
    checkRate(commissionRate);
    await _db.transaction(() async {
      await _requireInProcess(layawayId);
      final total = paymentLines.fold<int>(0, (sum, l) => sum + l.amount);
      final commissionAmount = (total * commissionRate / 100).round();

      final paymentId = await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              layawayId: Value(layawayId),
              totalAmount: Value(total),
              commissionRate: Value(commissionRate),
              commissionAmount: Value(commissionAmount),
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
                type: 'LAYAWAY_PAYMENT',
                amount: line.amount,
                method: Value(line.method),
                detail: Value('Abono apartado #$layawayId'),
                refType: 'LAYAWAY',
                refId: layawayId,
              ),
            );

        await creditSupplierIfDirectPayment(
          _db,
          line,
          detail: 'Pago directo desde abono apartado #$layawayId',
        );
      }
    });
  }

  /// Cancela un apartado que aún no tiene abonos: libera la reserva de
  /// stock sin generar ningún movimiento de caja.
  Future<void> cancelWithoutInvoice(int layawayId) async {
    await _db.transaction(() async {
      final layaway =
          await (_db.select(_db.layaways)..where((l) => l.id.equals(layawayId))).getSingle();
      if (layaway.state != 'IN_PROCESS') {
        throw StateError('Solo se pueden cancelar apartados en proceso.');
      }

      final paid = await (_db.selectOnly(_db.payments)
            ..addColumns([_db.payments.totalAmount.sum()])
            ..where(_db.payments.layawayId.equals(layawayId)))
          .map((row) => row.read(_db.payments.totalAmount.sum()) ?? 0)
          .getSingle();
      if (paid > 0) {
        throw StateError('Este apartado ya tiene abonos: usa "Devolver" en su lugar.');
      }

      await _releaseReservation(layawayId, layaway.warehouseId);

      await (_db.update(_db.layaways)..where((l) => l.id.equals(layawayId)))
          .write(const LayawaysCompanion(state: Value('CANCELLED_NO_INVOICE')));
    });
  }

  /// Devuelve un apartado con abonos: libera la reserva y saca de caja
  /// todo lo que el cliente había pagado.
  Future<void> returnLayaway({required int layawayId, required String reason}) async {
    await _db.transaction(() async {
      final layaway =
          await (_db.select(_db.layaways)..where((l) => l.id.equals(layawayId))).getSingle();
      if (layaway.state != 'IN_PROCESS') {
        throw StateError('Solo se pueden devolver apartados en proceso.');
      }

      final paid = await (_db.selectOnly(_db.payments)
            ..addColumns([_db.payments.totalAmount.sum()])
            ..where(_db.payments.layawayId.equals(layawayId)))
          .map((row) => row.read(_db.payments.totalAmount.sum()) ?? 0)
          .getSingle();
      if (paid <= 0) {
        throw StateError('El apartado no tiene abonos para devolver.');
      }

      await _releaseReservation(layawayId, layaway.warehouseId);

      await _db.into(_db.layawayReturns).insert(
            LayawayReturnsCompanion.insert(
              layawayId: layawayId,
              reason: Value(reason),
              state: const Value('CONFIRMED'),
              totalRefund: Value(paid),
            ),
          );

      // Se devuelve por las mismas formas de pago de cada abono.
      final payments =
          await (_db.select(_db.payments)..where((p) => p.layawayId.equals(layawayId))).get();
      await refundPaymentLines(
        _db,
        payments: payments,
        layawayId: layawayId,
        fallbackAmount: paid,
        type: 'LAYAWAY_REFUND',
        refType: 'LAYAWAY_RETURN',
        refId: layawayId,
        detail: 'Devolución apartado #$layawayId: $reason',
      );

      await (_db.update(_db.layaways)..where((l) => l.id.equals(layawayId)))
          .write(const LayawaysCompanion(state: Value('CANCELLED_NO_INVOICE')));
    });
  }

  Future<void> _releaseReservation(int layawayId, int warehouseId) async {
    final items = await (_db.select(_db.layawayItems)
          ..where((i) => i.layawayId.equals(layawayId)))
        .get();
    for (final it in items) {
      final stock = await (_db.select(_db.stock)
            ..where((s) =>
                s.productId.equals(it.productId) & s.warehouseId.equals(warehouseId)))
          .getSingleOrNull();
      if (stock != null) {
        final newReserved = stock.reservedQuantity - it.quantity;
        await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
          StockCompanion(reservedQuantity: Value(newReserved < 0 ? 0 : newReserved)),
        );
      }
    }
  }

  /// Factura el apartado ya saldado: crea la Venta asociada para que quede
  /// contabilizada (aparece en Ventas, alimenta comisiones y reportes).
  /// NO descuenta el stock físico todavía ni consume lotes FIFO — el
  /// mueble sigue reservado en bodega hasta que se marque "Entregado al
  /// cliente" (ver setDelivered), porque pagar el saldo completo no es lo
  /// mismo que ya haber entregado el mueble. Tampoco genera un nuevo
  /// movimiento de caja: el dinero ya entró como abonos.
  Future<int> invoiceToSale(int layawayId) async {
    return _db.transaction(() async {
      final layaway =
          await (_db.select(_db.layaways)..where((l) => l.id.equals(layawayId))).getSingle();
      if (layaway.state != 'IN_PROCESS') {
        throw StateError('Solo se pueden facturar apartados en proceso.');
      }

      final items = await (_db.select(_db.layawayItems)
            ..where((i) => i.layawayId.equals(layawayId)))
          .get();
      if (items.isEmpty) {
        throw StateError('El apartado no tiene productos.');
      }

      final totals = await () async {
        final total = await (_db.selectOnly(_db.layawayItems)
              ..addColumns([_db.layawayItems.lineTotal.sum()])
              ..where(_db.layawayItems.layawayId.equals(layawayId)))
            .map((row) => row.read(_db.layawayItems.lineTotal.sum()) ?? 0)
            .getSingle();
        final paid = await (_db.selectOnly(_db.payments)
              ..addColumns([_db.payments.totalAmount.sum()])
              ..where(_db.payments.layawayId.equals(layawayId)))
            .map((row) => row.read(_db.payments.totalAmount.sum()) ?? 0)
            .getSingle();
        return (total: total, paid: paid);
      }();

      if (totals.paid < totals.total) {
        throw StateError('El apartado todavía tiene saldo pendiente.');
      }

      final saleNumberSource = await _db.select(_db.sales).get();
      var maxNumber = 0;
      for (final s in saleNumberSource) {
        final n = int.tryParse(s.number);
        if (n != null && n > maxNumber) maxNumber = n;
      }
      final number = (maxNumber + 1).toString().padLeft(4, '0');

      final saleId = await _db.into(_db.sales).insert(
            SalesCompanion.insert(
              number: number,
              customerId: layaway.customerId,
              warehouseId: layaway.warehouseId,
              employeeId: Value(layaway.employeeId),
              notes: Value('Generada desde apartado #$layawayId'),
              state: const Value('CONFIRMED'),
              subtotal: Value(totals.total),
              total: Value(totals.total),
            ),
          );

      for (final it in items) {
        await _db.into(_db.saleItems).insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: it.productId,
                quantity: it.quantity,
                unitPrice: it.unitPrice,
                discount: Value(it.discount),
                lineTotal: Value(it.lineTotal),
              ),
            );
      }

      await (_db.update(_db.layaways)..where((l) => l.id.equals(layawayId))).write(
        LayawaysCompanion(
          state: const Value('INVOICED'),
          saleId: Value(saleId),
        ),
      );

      return saleId;
    });
  }

  /// Marca el apartado como entregado. Solo en este momento (no al
  /// facturar) se consumen físicamente los lotes FIFO, se descuenta el
  /// stock real y se libera la reserva — porque hasta que el cliente no se
  /// lleva el mueble, sigue siendo un compromiso, no una salida física.
  /// Devuelve los avisos de unidades entregadas sin inventario registrado.
  Future<List<UncostedUnits>> setDelivered(int layawayId, bool delivered) async {
    final warnings = <UncostedUnits>[];
    await _db.transaction(() async {
      final layaway =
          await (_db.select(_db.layaways)..where((l) => l.id.equals(layawayId))).getSingle();

      if (layaway.state == 'RETURNED') {
        throw StateError('La venta de este apartado fue devuelta: ya no se puede entregar.');
      }
      if (layaway.saleId != null) {
        final sale = await (_db.select(_db.sales)..where((s) => s.id.equals(layaway.saleId!)))
            .getSingleOrNull();
        if (sale != null && sale.isReturn) {
          throw StateError('La venta de este apartado fue devuelta: ya no se puede entregar.');
        }
      }

      // Idempotente: si ya hay salidas de inventario de este apartado (se
      // entregó antes), nunca se vuelve a descontar, aunque el indicador
      // "entregado" se haya desmarcado y vuelto a marcar.
      final alreadyFulfilled = await (_db.select(_db.stockMovements)
            ..where((m) => m.refType.equals('LAYAWAY') & m.refId.equals(layawayId))
            ..limit(1))
          .getSingleOrNull();

      final shouldFulfill = delivered &&
          !layaway.delivered &&
          alreadyFulfilled == null &&
          layaway.state == 'INVOICED' &&
          layaway.saleId != null;

      if (shouldFulfill) {
        final saleId = layaway.saleId!;
        final items =
            await (_db.select(_db.saleItems)..where((i) => i.saleId.equals(saleId))).get();

        for (final it in items) {
          final w = await consumeItemFifo(
            _db,
            item: it,
            warehouseId: layaway.warehouseId,
            refType: 'LAYAWAY',
            refId: layawayId,
            note: 'Entrega apartado #$layawayId',
            releaseReservation: true,
          );
          if (w != null) warnings.add(w);
        }
      }

      await (_db.update(_db.layaways)..where((l) => l.id.equals(layawayId))).write(
        LayawaysCompanion(
          delivered: Value(delivered),
          deliveredAt: Value(delivered ? DateTime.now() : null),
        ),
      );
    });
    return warnings;
  }
}

final layawaysRepositoryProvider = Provider<LayawaysRepository>((ref) {
  return LayawaysRepository(ref.watch(databaseProvider));
});
