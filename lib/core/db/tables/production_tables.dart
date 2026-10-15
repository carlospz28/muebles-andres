import 'package:drift/drift.dart';

import 'layaway_tables.dart';
import 'people_tables.dart';
import 'sale_tables.dart';

/// Ficha de producción: seguimiento del proceso de fabricación de un
/// mueble a la medida (estructura, cortes, costura/tapizado), separado
/// del registro de venta. Puede nacer de una venta o apartado ya
/// existente (hereda cliente y precio), o quedar suelta para producir
/// antes de que exista una venta formal.
class ProductionOrders extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Tipo de mueble / descripción del producto a fabricar.
  TextColumn get productType => text().withLength(min: 1, max: 200)();

  IntColumn get customerId => integer().nullable().references(Customers, #id)();

  /// Venta o apartado de donde nació esta ficha, si aplica.
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  IntColumn get layawayId => integer().nullable().references(Layaways, #id)();

  DateTimeColumn get scheduledDate => dateTime().nullable()();
  DateTimeColumn get elaborationDate => dateTime().nullable()();
  DateTimeColumn get deliveryDate => dateTime().nullable()();

  IntColumn get salePrice => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().withDefault(const Constant(''))();

  /// 'IN_PROCESS' | 'DELIVERED' | 'CANCELLED'
  TextColumn get state => text().withDefault(const Constant('IN_PROCESS'))();
}

/// Cada ficha tiene exactamente 3 etapas fijas (ver los valores de
/// [stage] abajo), creadas automáticamente al crear la ficha. El costo de
/// mano de obra y el responsable se registran por etapa porque en el
/// taller normalmente cada etapa la hace una persona distinta.
class ProductionStages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productionOrderId => integer().references(ProductionOrders, #id)();

  /// 'ESTRUCTURA' | 'CORTES' | 'COSTURA_TAPIZADOS'
  TextColumn get stage => text()();

  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedDate => dateTime().nullable()();
  IntColumn get responsibleEmployeeId =>
      integer().nullable().references(Employees, #id)();
  IntColumn get laborCost => integer().withDefault(const Constant(0))();
}
