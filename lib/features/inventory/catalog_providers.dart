import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

final categoriesStreamProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.categories)..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

/// Productos filtrados por texto de búsqueda (nombre o SKU) — el buscador
/// que el cliente pidió en todos los módulos.
final productSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final productsStreamProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = ref.watch(productSearchProvider).trim();

  final q = db.select(db.products)
    ..orderBy([(p) => OrderingTerm.asc(p.name)]);

  if (query.isNotEmpty) {
    q.where((p) => p.name.contains(query) | p.sku.contains(query));
  }

  return q.watch();
});

class ProductStock {
  const ProductStock(this.product, this.quantity, this.reserved);
  final Product product;
  final int quantity;
  final int reserved;
  int get available => quantity - reserved;
}

/// Existencias actuales por producto (bodega única). Un producto que
/// nunca se ha comprado no tiene fila en Stock todavía, así que se
/// muestra en cero en vez de desaparecer de la lista.
final stockStreamProvider = StreamProvider.autoDispose<List<ProductStock>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = ref.watch(productSearchProvider).trim();

  final q = db.select(db.products).join([
    leftOuterJoin(db.stock, db.stock.productId.equalsExp(db.products.id)),
  ])
    ..where(db.products.isActive.equals(true))
    ..orderBy([OrderingTerm.asc(db.products.name)]);

  if (query.isNotEmpty) {
    q.where(db.products.name.contains(query) | db.products.sku.contains(query));
  }

  return q.watch().map((rows) {
    return rows.map((row) {
      final product = row.readTable(db.products);
      final stock = row.readTableOrNull(db.stock);
      return ProductStock(product, stock?.quantity ?? 0, stock?.reservedQuantity ?? 0);
    }).toList();
  });
});

class CatalogRepository {
  CatalogRepository(this._db);
  final AppDatabase _db;

  Future<int> saveCategory({int? id, required String name}) async {
    if (id == null) {
      return _db.into(_db.categories).insert(
            CategoriesCompanion.insert(name: name),
          );
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(name: Value(name)));
    return id;
  }

  Future<void> setCategoryActive(int id, bool active) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(isActive: Value(active)));
  }

  Future<String> _nextSku() async {
    final all = await _db.select(_db.products).get();
    var maxNumber = 0;
    for (final p in all) {
      final n = int.tryParse(p.sku);
      if (n != null && n > maxNumber) maxNumber = n;
    }
    var next = maxNumber + 1;
    final existingSkus = all.map((p) => p.sku).toSet();
    var code = next.toString().padLeft(4, '0');
    while (existingSkus.contains(code)) {
      next++;
      code = next.toString().padLeft(4, '0');
    }
    return code;
  }

  Future<int> saveProduct({
    int? id,
    required String name,
    required int categoryId,
    required int price,
    String description = '',
  }) async {
    if (id == null) {
      final sku = await _nextSku();
      return _db.into(_db.products).insert(
            ProductsCompanion.insert(
              sku: sku,
              name: name,
              categoryId: categoryId,
              price: Value(price),
              description: Value(description),
            ),
          );
    }
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        name: Value(name),
        categoryId: Value(categoryId),
        price: Value(price),
        description: Value(description),
      ),
    );
    return id;
  }

  Future<void> setProductActive(int id, bool active) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id)))
        .write(ProductsCompanion(isActive: Value(active)));
  }

  /// Ingreso manual de inventario (ej. lo que ya había físicamente en el
  /// almacén, o mercancía que entra sin ser una compra formal): crea su
  /// propio lote para costeo FIFO y suma stock, pero — a diferencia de
  /// una Compra — NO toca caja ni genera deuda con ningún proveedor,
  /// porque no hay una salida de dinero real asociada a este movimiento.
  /// El costo de transporte (si aplica) se reparte entre las unidades
  /// para que el costo de cada unidad refleje lo que realmente costó
  /// traerla, y así la utilidad calculada en Análisis sea correcta.
  Future<void> addInventoryEntry({
    required int productId,
    required int warehouseId,
    required int quantity,
    required int unitCost,
    int transportCost = 0,
    String note = '',
  }) async {
    final effectiveUnitCost = unitCost + (transportCost / quantity).round();

    await _db.transaction(() async {
      final lotId = await _db.into(_db.productLots).insert(
            ProductLotsCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              quantityReceived: quantity,
              quantityRemaining: quantity,
              unitCost: effectiveUnitCost,
            ),
          );

      final stock = await (_db.select(_db.stock)
            ..where((s) =>
                s.productId.equals(productId) & s.warehouseId.equals(warehouseId)))
          .getSingleOrNull();

      if (stock == null) {
        await _db.into(_db.stock).insert(
              StockCompanion.insert(
                productId: productId,
                warehouseId: warehouseId,
                quantity: Value(quantity),
              ),
            );
      } else {
        await (_db.update(_db.stock)..where((s) => s.id.equals(stock.id))).write(
          StockCompanion(quantity: Value(stock.quantity + quantity)),
        );
      }

      await _db.into(_db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              type: 'ADJ',
              quantity: quantity,
              lotId: Value(lotId),
              refType: 'ADJUSTMENT',
              refId: lotId,
              note: Value(note.isEmpty ? 'Ingreso de inventario' : note),
            ),
          );
    });
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(databaseProvider));
});
