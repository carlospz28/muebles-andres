import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

/// Las 3 etapas fijas del proceso de fabricación, en el orden en que se
/// muestran siempre.
const List<String> kProductionStages = [
  'ESTRUCTURA',
  'CORTES',
  'COSTURA_TAPIZADOS',
];

String productionStageLabel(String stage) {
  switch (stage) {
    case 'ESTRUCTURA':
      return 'Estructura';
    case 'CORTES':
      return 'Cortes';
    case 'COSTURA_TAPIZADOS':
      return 'Costura / Tapizados';
    default:
      return stage;
  }
}

class ProductionOrderListItem {
  ProductionOrderListItem(this.order, this.customerName);
  final ProductionOrder order;
  final String? customerName;
}

final productionOrdersStreamProvider =
    StreamProvider.autoDispose<List<ProductionOrderListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.productionOrders).join([
    leftOuterJoin(
      db.customers,
      db.customers.id.equalsExp(db.productionOrders.customerId),
    ),
  ])
    ..orderBy([OrderingTerm.desc(db.productionOrders.id)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => ProductionOrderListItem(
              row.readTable(db.productionOrders),
              row.readTableOrNull(db.customers)?.name,
            ))
        .toList();
  });
});

final productionOrderByIdProvider =
    StreamProvider.autoDispose.family<ProductionOrder, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productionOrders)..where((o) => o.id.equals(id)))
      .watchSingle();
});

final productionOrderCustomerProvider =
    StreamProvider.autoDispose.family<Customer?, int?>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  if (customerId == null) return Stream.value(null);
  return (db.select(db.customers)..where((c) => c.id.equals(customerId)))
      .watchSingleOrNull();
});

class ProductionStageView {
  ProductionStageView(this.stage, this.employeeName);
  final ProductionStage stage;
  final String? employeeName;
}

final productionStagesProvider =
    StreamProvider.autoDispose.family<List<ProductionStageView>, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.productionStages).join([
    leftOuterJoin(
      db.employees,
      db.employees.id.equalsExp(db.productionStages.responsibleEmployeeId),
    ),
  ])
    ..where(db.productionStages.productionOrderId.equals(orderId));

  return query.watch().map((rows) {
    final views = rows
        .map((row) => ProductionStageView(
              row.readTable(db.productionStages),
              row.readTableOrNull(db.employees)?.name,
            ))
        .toList();
    views.sort((a, b) =>
        kProductionStages.indexOf(a.stage.stage).compareTo(kProductionStages.indexOf(b.stage.stage)));
    return views;
  });
});

class ProductionRepository {
  ProductionRepository(this._db);
  final AppDatabase _db;

  Future<int> _createOrder({
    required String productType,
    int? customerId,
    int? saleId,
    int? layawayId,
    int salePrice = 0,
  }) async {
    return _db.transaction(() async {
      final orderId = await _db.into(_db.productionOrders).insert(
            ProductionOrdersCompanion.insert(
              productType: productType,
              customerId: Value(customerId),
              saleId: Value(saleId),
              layawayId: Value(layawayId),
              salePrice: Value(salePrice),
            ),
          );

      for (final stage in kProductionStages) {
        await _db.into(_db.productionStages).insert(
              ProductionStagesCompanion.insert(
                productionOrderId: orderId,
                stage: stage,
              ),
            );
      }

      return orderId;
    });
  }

  Future<int> createStandalone({
    required String productType,
    int? customerId,
  }) {
    return _createOrder(productType: productType, customerId: customerId);
  }

  Future<int> createFromSale(int saleId) async {
    final sale =
        await (_db.select(_db.sales)..where((s) => s.id.equals(saleId))).getSingle();
    return _createOrder(
      productType: '',
      customerId: sale.customerId,
      saleId: saleId,
      salePrice: sale.total,
    );
  }

  Future<int> createFromLayaway(int layawayId) async {
    final layaway = await (_db.select(_db.layaways)
          ..where((l) => l.id.equals(layawayId)))
        .getSingle();
    final total = await (_db.selectOnly(_db.layawayItems)
          ..addColumns([_db.layawayItems.lineTotal.sum()])
          ..where(_db.layawayItems.layawayId.equals(layawayId)))
        .map((row) => row.read(_db.layawayItems.lineTotal.sum()) ?? 0)
        .getSingle();
    return _createOrder(
      productType: '',
      customerId: layaway.customerId,
      layawayId: layawayId,
      salePrice: total,
    );
  }

  Future<void> updateOrder({
    required int id,
    String? productType,
    Value<int?> customerId = const Value.absent(),
    Value<DateTime?> scheduledDate = const Value.absent(),
    Value<DateTime?> elaborationDate = const Value.absent(),
    Value<int>? salePrice,
    String? notes,
  }) async {
    await (_db.update(_db.productionOrders)..where((o) => o.id.equals(id))).write(
      ProductionOrdersCompanion(
        productType: productType == null ? const Value.absent() : Value(productType),
        customerId: customerId,
        scheduledDate: scheduledDate,
        elaborationDate: elaborationDate,
        salePrice: salePrice ?? const Value.absent(),
        notes: notes == null ? const Value.absent() : Value(notes),
      ),
    );
  }

  Future<void> updateStage({
    required int stageId,
    required bool completed,
    int? responsibleEmployeeId,
    required int laborCost,
  }) async {
    await (_db.update(_db.productionStages)..where((s) => s.id.equals(stageId))).write(
      ProductionStagesCompanion(
        completed: Value(completed),
        completedDate: Value(completed ? DateTime.now() : null),
        responsibleEmployeeId: Value(responsibleEmployeeId),
        laborCost: Value(laborCost),
      ),
    );
  }

  Future<void> markDelivered(int id) async {
    await (_db.update(_db.productionOrders)..where((o) => o.id.equals(id))).write(
      ProductionOrdersCompanion(
        state: const Value('DELIVERED'),
        deliveryDate: Value(DateTime.now()),
      ),
    );
  }

  Future<void> cancel(int id) async {
    await (_db.update(_db.productionOrders)..where((o) => o.id.equals(id)))
        .write(const ProductionOrdersCompanion(state: Value('CANCELLED')));
  }

  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.productionStages)
            ..where((s) => s.productionOrderId.equals(id)))
          .go();
      await (_db.delete(_db.productionOrders)..where((o) => o.id.equals(id))).go();
    });
  }
}

final productionRepositoryProvider = Provider<ProductionRepository>((ref) {
  return ProductionRepository(ref.watch(databaseProvider));
});
