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

  /// Deuda que ya existía con este proveedor antes de empezar a usar la
  /// app (para cargar proveedores que ya se les debía algo). Se suma a lo
  /// comprado desde acá para calcular la deuda total.
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
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

/// Retiro de dinero de una cuenta de consignación (ej. sacar del banco
/// para tener efectivo en la caja). Reduce el saldo de la cuenta; el
/// dinero retirado se registra como ingreso de efectivo en el libro de
/// caja, porque pasa a ser billete físico disponible.
class AccountWithdrawals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(PaymentAccounts, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get amount => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
}
