import 'package:drift/drift.dart';

import 'catalog_tables.dart';

/// Un Kit es una plantilla (ej. "Comedor 6 puestos") que agrupa productos
/// que ya existen como productos normales (mesa, sillas, vidrio...). Al
/// vender un kit, se expande en líneas de venta normales por cada
/// componente activo, así que el stock de cada componente sigue siendo
/// el mismo stock individual del producto (silla, vidrio, etc.).
class Kits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get description => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Componentes de un kit. `includedByDefault` controla si el componente
/// viene marcado al agregar el kit a una venta/apartado (ej. el vidrio
/// puede venir desactivado por defecto porque se cobra aparte).
class KitComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get kitId => integer().references(Kits, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get defaultQuantity => integer().withDefault(const Constant(1))();
  BoolColumn get includedByDefault =>
      boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
