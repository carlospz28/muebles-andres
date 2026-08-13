import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

final kitsStreamProvider = StreamProvider.autoDispose<List<Kit>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.kits)..orderBy([(k) => OrderingTerm.asc(k.name)])).watch();
});

final kitByIdProvider = StreamProvider.autoDispose.family<Kit, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.kits)..where((k) => k.id.equals(id))).watchSingle();
});

class KitComponentView {
  KitComponentView(this.component, this.product);
  final KitComponent component;
  final Product product;
}

final kitComponentsProvider =
    StreamProvider.autoDispose.family<List<KitComponentView>, int>((ref, kitId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.kitComponents).join([
    innerJoin(db.products, db.products.id.equalsExp(db.kitComponents.productId)),
  ])
    ..where(db.kitComponents.kitId.equals(kitId))
    ..orderBy([OrderingTerm.asc(db.kitComponents.sortOrder)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => KitComponentView(
              row.readTable(db.kitComponents),
              row.readTable(db.products),
            ))
        .toList();
  });
});

class KitsRepository {
  KitsRepository(this._db);
  final AppDatabase _db;

  Future<int> saveKit({int? id, required String name, String description = ''}) async {
    if (id == null) {
      return _db.into(_db.kits).insert(
            KitsCompanion.insert(name: name, description: Value(description)),
          );
    }
    await (_db.update(_db.kits)..where((k) => k.id.equals(id))).write(
      KitsCompanion(name: Value(name), description: Value(description)),
    );
    return id;
  }

  Future<void> setKitActive(int id, bool active) async {
    await (_db.update(_db.kits)..where((k) => k.id.equals(id)))
        .write(KitsCompanion(isActive: Value(active)));
  }

  Future<void> addComponent({
    required int kitId,
    required int productId,
    int defaultQuantity = 1,
    bool includedByDefault = true,
  }) async {
    await _db.into(_db.kitComponents).insert(
          KitComponentsCompanion.insert(
            kitId: kitId,
            productId: productId,
            defaultQuantity: Value(defaultQuantity),
            includedByDefault: Value(includedByDefault),
          ),
        );
  }

  Future<void> removeComponent(int componentId) async {
    await (_db.delete(_db.kitComponents)..where((c) => c.id.equals(componentId))).go();
  }

  Future<void> setComponentIncludedByDefault(int componentId, bool included) async {
    await (_db.update(_db.kitComponents)..where((c) => c.id.equals(componentId)))
        .write(KitComponentsCompanion(includedByDefault: Value(included)));
  }
}

final kitsRepositoryProvider = Provider<KitsRepository>((ref) {
  return KitsRepository(ref.watch(databaseProvider));
});
