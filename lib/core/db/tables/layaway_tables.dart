import 'package:drift/drift.dart';

import 'catalog_tables.dart';
import 'inventory_tables.dart';
import 'kit_tables.dart';
import 'people_tables.dart';
import 'sale_tables.dart';

class Layaways extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get employeeId => integer().nullable().references(Employees, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// 'IN_PROCESS' | 'CANCELLED_NO_INVOICE' | 'INVOICED'
  TextColumn get state => text().withDefault(const Constant('IN_PROCESS'))();

  /// Venta generada al facturar el apartado (cuando queda saldado).
  IntColumn get saleId => integer().nullable().references(Sales, #id)();

  /// Igual que en Sales: pagado y entregado son cosas distintas.
  BoolColumn get delivered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
}

class LayawayItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get layawayId => integer().references(Layaways, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get kitId => integer().nullable().references(Kits, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get lineTotal => integer().withDefault(const Constant(0))();
}

class LayawayReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get layawayId => integer().references(Layaways, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get reason => text().withDefault(const Constant(''))();

  /// 'DRAFT' | 'CONFIRMED'
  TextColumn get state => text().withDefault(const Constant('DRAFT'))();
  IntColumn get totalRefund => integer().withDefault(const Constant(0))();
}
