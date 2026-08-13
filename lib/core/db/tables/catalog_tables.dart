import 'package:drift/drift.dart';

/// Categorías de productos (sofás, comedores, colchones, etc.)
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Productos individuales. Un producto puede ser un componente de un Kit
/// (ej. silla, vidrio) y venderse también por separado.
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().withLength(min: 1, max: 30)();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Precio de venta sugerido (pesos, sin decimales).
  IntColumn get price => integer().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Si es true, este producto es solo un componente de kit y no debería
  /// ofrecerse suelto en el buscador de ventas (configurable, no obligatorio).
  BoolColumn get soldStandalone =>
      boolean().withDefault(const Constant(true))();
}
