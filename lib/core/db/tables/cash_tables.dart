import 'package:drift/drift.dart';

import 'people_tables.dart';

/// Categorías de gasto, editables por el usuario (arriendo, servicios,
/// transporte, etc.)
class ExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(ExpenseCategories, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get amount => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 'CASH' | 'CONSIGNMENT' — con qué se pagó el gasto.
  TextColumn get method => text().withDefault(const Constant('CASH'))();

  /// Cuenta de consignación de la que salió el pago, si method es
  /// 'CONSIGNMENT'.
  IntColumn get accountId => integer().nullable().references(PaymentAccounts, #id)();
}

/// Libro mayor único de caja: todo ingreso o salida de efectivo queda
/// registrado aquí (positivo = entra dinero, negativo = sale dinero).
/// Esto es lo que alimenta las gráficas de "cuánto se gana por semana/mes"
/// y el cierre de caja diario.
class CashMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  /// 'SALE' | 'LAYAWAY_PAYMENT' | 'EXPENSE' | 'SUPPLIER_PAYMENT' |
  /// 'SALE_REFUND' | 'LAYAWAY_REFUND' | 'PURCHASE' | 'OPENING' |
  /// 'COMMISSION_PAYMENT'
  TextColumn get type => text()();

  /// Monto con signo: positivo = ingreso, negativo = salida.
  IntColumn get amount => integer()();

  /// 'CASH' | 'CONSIGNMENT' | 'SUPPLIER'. Determina si este movimiento
  /// afecta el efectivo físico de la caja ('CASH'), fue por
  /// transferencia/consignación ('CONSIGNMENT'), o nunca pasó por la
  /// caja/cuenta del negocio porque fue plata enviada directo a un
  /// proveedor ('SUPPLIER') — cuenta como venta pero no como billete
  /// físico ni como consignación.
  TextColumn get method => text().withDefault(const Constant('CASH'))();

  TextColumn get detail => text().withDefault(const Constant(''))();

  /// Tabla e id del documento que originó este movimiento, para trazar
  /// el origen exacto (auditoría).
  TextColumn get refType => text()();
  IntColumn get refId => integer()();
}

/// Caja diaria: base con la que se abre el día.
class CashSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().unique()();
  IntColumn get openingCash => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

/// Activos fijos del negocio (mobiliario propio, equipos, vehículos).
class FixedAssets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 150)();

  /// 'FURNITURE' | 'EQUIPMENT' | 'VEHICLE' | 'OTHER'
  TextColumn get category => text().withDefault(const Constant('OTHER'))();
  DateTimeColumn get purchaseDate =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get cost => integer()();
  IntColumn get accumulatedDepreciation =>
      integer().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
}
