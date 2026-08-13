import 'package:drift/drift.dart';

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get document => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Vendedores / empleados. Se usan para asignar comisiones.
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get document => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Porcentaje de comisión que se aplica solo al asignar este vendedor a
  /// una venta o abono — editable ahí caso por caso, y editable aquí para
  /// cuando cambie de forma general (ej. sube o baja de un mes a otro).
  RealColumn get defaultCommissionRate => real().withDefault(const Constant(0))();
}

class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get document => text().nullable()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Cuentas bancarias/destinos a los que se les hacen consignaciones
/// (propias, de proveedores, o del negocio). Se usan tanto para pagos
/// de clientes por consignación como para abonos a proveedores.
class PaymentAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().withLength(min: 1, max: 120)();
  TextColumn get bankName => text().withDefault(const Constant(''))();
  TextColumn get accountNumber => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
