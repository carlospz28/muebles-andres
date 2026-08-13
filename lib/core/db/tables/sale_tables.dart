import 'package:drift/drift.dart';

import 'catalog_tables.dart';
import 'inventory_tables.dart';
import 'kit_tables.dart';
import 'people_tables.dart';

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get number => text().withLength(min: 1, max: 30)();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get employeeId => integer().nullable().references(Employees, #id)();

  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  /// 'DRAFT' | 'CONFIRMED' | 'CANCELLED'
  TextColumn get state => text().withDefault(const Constant('DRAFT'))();

  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discountTotal => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();

  /// Porcentaje de comisión sobre el total (editable, no fijo).
  RealColumn get commissionRate => real().withDefault(const Constant(0))();
  IntColumn get commissionAmount => integer().withDefault(const Constant(0))();

  BoolColumn get isReturn => boolean().withDefault(const Constant(false))();

  /// Estado de entrega, independiente del pago: el cliente puede terminar
  /// de pagar y reclamar el mueble días después.
  BoolColumn get delivered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deliveredAt => dateTime().nullable()();

  TextColumn get notes => text().withDefault(const Constant(''))();
}

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get productId => integer().references(Products, #id)();

  /// Si esta línea vino de expandir un Kit, referencia al kit de origen
  /// (solo para mostrar agrupado en el recibo; el stock sigue siendo el
  /// del producto individual).
  IntColumn get kitId => integer().nullable().references(Kits, #id)();

  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get lineTotal => integer().withDefault(const Constant(0))();

  /// Costo total tomado de los lotes FIFO consumidos (para utilidad real).
  IntColumn get costTotal => integer().withDefault(const Constant(0))();
}

/// Detalle de qué lote(s) surtieron cada línea de venta (una línea puede
/// tomar cantidad de más de un lote si el primero no alcanza).
class SaleItemLotConsumptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleItemId => integer().references(SaleItems, #id)();
  IntColumn get lotId => integer()();
  IntColumn get quantity => integer()();
  IntColumn get unitCost => integer()();
}

class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get reason => text().withDefault(const Constant(''))();

  /// 'PENDING' | 'CONFIRMED' | 'CANCELLED'
  TextColumn get state => text().withDefault(const Constant('PENDING'))();
  IntColumn get refundAmount => integer().withDefault(const Constant(0))();
}
