import 'package:drift/drift.dart';

import 'catalog_tables.dart';

class Warehouses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get location => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Existencias actuales por producto/bodega.
/// `quantity` = físico total. `reservedQuantity` = reservado por apartados.
/// Disponible = quantity - reservedQuantity.
class Stock extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get reservedQuantity => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {productId, warehouseId},
      ];
}

/// Lotes de mercancía (costeo FIFO). Cada entrada de compra crea un lote
/// con su propio costo unitario; las ventas consumen primero el lote más
/// antiguo con existencia > 0. Cuando un lote se agota, la siguiente venta
/// pasa a tomar el costo del lote nuevo automáticamente.
class ProductLots extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();

  /// Nulo si el lote se creó como saldo inicial (no viene de una compra).
  IntColumn get purchaseId => integer().nullable()();

  IntColumn get quantityReceived => integer()();
  IntColumn get quantityRemaining => integer()();

  /// Costo unitario de este lote (pesos, sin decimales).
  IntColumn get unitCost => integer()();

  DateTimeColumn get receivedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Auditoría de todo movimiento de inventario (entradas, salidas, ajustes,
/// traslados, ventas, devoluciones). No actualiza stock por sí sola; el
/// stock lo actualizan las operaciones (Purchase.confirm, Sale.confirm, etc.)
/// dentro de una transacción, igual que en el sistema anterior.
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();

  /// 'IN' | 'OUT' | 'ADJ'
  TextColumn get type => text()();
  IntColumn get quantity => integer()();

  /// Lote del que salió/entró la mercancía (si aplica).
  IntColumn get lotId => integer().nullable().references(ProductLots, #id)();

  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Referencia al documento origen: 'SALE' | 'PURCHASE' | 'LAYAWAY' |
  /// 'SALE_RETURN' | 'LAYAWAY_RETURN' | 'ADJUSTMENT'
  TextColumn get refType => text()();
  IntColumn get refId => integer()();
}
