import 'package:drift/drift.dart';

import 'layaway_tables.dart';
import 'people_tables.dart';
import 'sale_tables.dart';

/// Un evento de pago: el pago de contado de una venta, o un abono a un
/// apartado. Exactamente uno de saleId/layawayId debe estar presente
/// (se valida en el repositorio, no aquí).
///
/// Un mismo Payment puede tener varias PaymentLines para soportar pago
/// mixto (parte efectivo, parte consignación) tal como lo pidió el
/// cliente.
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  IntColumn get layawayId => integer().nullable().references(Layaways, #id)();

  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get totalAmount => integer().withDefault(const Constant(0))();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Comisión sobre este abono/pago (para apartados: "la comisión se
  /// calcula sobre el abono que hacen", no sobre el total del apartado).
  RealColumn get commissionRate => real().withDefault(const Constant(0))();
  IntColumn get commissionAmount => integer().withDefault(const Constant(0))();
}

/// Cada línea de un Payment: método (efectivo o consignación) + monto +
/// cuenta destino si es consignación.
class PaymentLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId => integer().references(Payments, #id)();

  /// 'CASH' | 'CONSIGNMENT'
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  IntColumn get accountId =>
      integer().nullable().references(PaymentAccounts, #id)();
}
