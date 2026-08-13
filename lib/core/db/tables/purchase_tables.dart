import 'package:drift/drift.dart';

import 'catalog_tables.dart';
import 'inventory_tables.dart';
import 'people_tables.dart';

/// Compras (entrada de mercancía). Cada Purchase confirmada crea un
/// ProductLot por ítem con el costo de esa entrada — así, cuando un lote
/// viejo se agota, la siguiente venta automáticamente pasa a cobrar costo
/// contra el lote nuevo (FIFO), en vez de mezclar costos como un promedio.
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get number => text().withLength(min: 1, max: 30)();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  /// 'DRAFT' | 'CONFIRMED' | 'CANCELLED'
  TextColumn get state => text().withDefault(const Constant('DRAFT'))();

  /// 'CASH' | 'CREDIT'
  TextColumn get paymentType => text().withDefault(const Constant('CASH'))();

  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().withDefault(const Constant(''))();
}

class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitCost => integer()();
  IntColumn get lineTotal => integer().withDefault(const Constant(0))();
}

/// Abonos a proveedores (efectivo o consignación/transferencia).
class SupplierPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get purchaseId =>
      integer().nullable().references(Purchases, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get amount => integer()();

  /// 'CASH' | 'CONSIGNMENT'
  TextColumn get method => text().withDefault(const Constant('CASH'))();
  IntColumn get accountId =>
      integer().nullable().references(PaymentAccounts, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
}
