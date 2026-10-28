import 'package:drift/drift.dart';

import '../db/database.dart';
import 'xlsx_writer.dart';

/// Arma el Excel de inventario: existencias de cada producto con el costo
/// que se le asignó al ingresarlo (en "Ingreso de inventario" o en una
/// compra, guardado por lotes FIFO), su valor a costo y a precio de venta,
/// y el detalle de cada lote. Devuelve los bytes del .xlsx.
Future<List<int>> buildInventoryExcel(AppDatabase db) async {
  final products = await (db.select(db.products).join([
    innerJoin(db.categories, db.categories.id.equalsExp(db.products.categoryId)),
  ])
        ..where(db.products.isActive.equals(true))
        ..orderBy([OrderingTerm.asc(db.categories.name), OrderingTerm.asc(db.products.name)]))
      .get();
  final stock = await db.select(db.stock).get();
  final lots = await (db.select(db.productLots)..orderBy([(l) => OrderingTerm.asc(l.receivedAt)])).get();
  final purchases = {for (final p in await db.select(db.purchases).get()) p.id: p};

  final qtyByProduct = <int, int>{};
  final reservedByProduct = <int, int>{};
  for (final s in stock) {
    qtyByProduct[s.productId] = (qtyByProduct[s.productId] ?? 0) + s.quantity;
    reservedByProduct[s.productId] = (reservedByProduct[s.productId] ?? 0) + s.reservedQuantity;
  }

  final xlsx = XlsxWriter();
  final stamp = _stamp(DateTime.now());

  // ------------------------------------------------------------ Inventario
  final inv = xlsx.addSheet('Inventario');
  inv.row(['Inventario y costos'], bold: true);
  inv.row(['Muebles Omar · corte al $stamp']);
  inv.row(['Costo unitario: el del lote más antiguo que queda (el próximo que sale al vender, FIFO). '
      'Costo promedio: promedio de todo lo que queda.']);
  inv.row([]);
  inv.row([
    'Código',
    'Producto',
    'Categoría',
    'Existencia',
    'Apartado',
    'Disponible',
    'Costo unitario',
    'Costo promedio',
    'Valor a costo',
    'Precio de venta',
    'Valor a precio de venta',
    'Ganancia por unidad',
    'Margen %',
  ], header: true);

  var totalQty = 0, totalCostValue = 0, totalSaleValue = 0;
  for (final r in products) {
    final p = r.readTable(db.products);
    final c = r.readTable(db.categories);
    final qty = qtyByProduct[p.id] ?? 0;
    final reserved = reservedByProduct[p.id] ?? 0;
    final open = lots.where((l) => l.productId == p.id && l.quantityRemaining > 0).toList();
    final remaining = open.fold<int>(0, (a, l) => a + l.quantityRemaining);
    final costValue = open.fold<int>(0, (a, l) => a + l.quantityRemaining * l.unitCost);
    final fifoCost = open.isEmpty ? null : open.first.unitCost;
    final avgCost = remaining == 0 ? null : (costValue / remaining).round();
    final unitCostForMargin = fifoCost ?? avgCost;
    final profit = unitCostForMargin == null ? null : p.price - unitCostForMargin;
    final margin = profit == null || p.price == 0 ? null : double.parse((profit * 100 / p.price).toStringAsFixed(1));

    totalQty += qty;
    totalCostValue += costValue;
    totalSaleValue += qty * p.price;
    inv.row([
      p.sku,
      p.name,
      c.name,
      qty,
      reserved,
      qty - reserved,
      fifoCost == null ? 'Sin costo' : Money(fifoCost),
      avgCost == null ? null : Money(avgCost),
      Money(costValue),
      Money(p.price),
      Money(qty * p.price),
      profit == null ? null : Money(profit),
      margin,
    ]);
  }
  inv.row([
    'TOTAL',
    null,
    null,
    totalQty,
    null,
    null,
    null,
    null,
    Money(totalCostValue),
    null,
    Money(totalSaleValue),
  ], bold: true);
  inv.setWidths([9, 34, 18, 11, 10, 11, 15, 15, 16, 15, 20, 17, 10]);

  // -------------------------------------------------------- Costo por lote
  final productById = {for (final r in products) r.readTable(db.products).id: r.readTable(db.products)};
  final lotSheet = xlsx.addSheet('Costo por lote');
  lotSheet.row(['Costo de cada ingreso de mercancía (lotes)'], bold: true);
  lotSheet.row(['Muebles Omar · corte al $stamp']);
  lotSheet.row([]);
  lotSheet.row([
    'Código',
    'Producto',
    'Fecha de ingreso',
    'Origen',
    'Cantidad ingresada',
    'Cantidad que queda',
    'Costo unitario',
    'Valor de lo que queda',
  ], header: true);
  var lotsValue = 0;
  final sortedLots = [...lots]..sort((a, b) {
      final pa = productById[a.productId]?.name ?? '';
      final pb = productById[b.productId]?.name ?? '';
      final byName = pa.compareTo(pb);
      return byName != 0 ? byName : a.receivedAt.compareTo(b.receivedAt);
    });
  for (final l in sortedLots) {
    final p = productById[l.productId];
    if (p == null) continue; // producto inactivo
    final purchase = l.purchaseId == null ? null : purchases[l.purchaseId];
    final value = l.quantityRemaining * l.unitCost;
    lotsValue += value;
    lotSheet.row([
      p.sku,
      p.name,
      l.receivedAt,
      purchase != null ? 'Compra ${purchase.number}' : 'Ingreso de inventario',
      l.quantityReceived,
      l.quantityRemaining,
      Money(l.unitCost),
      Money(value),
    ]);
  }
  lotSheet.row(['TOTAL', null, null, null, null, null, null, Money(lotsValue)], bold: true);
  lotSheet.setWidths([9, 34, 16, 22, 18, 18, 15, 20]);

  return xlsx.encode();
}

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
