import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

final expenseCategoriesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.expenseCategories)
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

class ExpenseListItem {
  ExpenseListItem(this.expense, this.categoryName);
  final Expense expense;
  final String categoryName;
}

final expensesStreamProvider = StreamProvider.autoDispose<List<ExpenseListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenses).join([
    innerJoin(db.expenseCategories,
        db.expenseCategories.id.equalsExp(db.expenses.categoryId)),
  ])
    ..orderBy([OrderingTerm.desc(db.expenses.date)]);

  return query.watch().map((rows) {
    return rows
        .map((row) => ExpenseListItem(
              row.readTable(db.expenses),
              row.readTable(db.expenseCategories).name,
            ))
        .toList();
  });
});

class ExpensesRepository {
  ExpensesRepository(this._db);
  final AppDatabase _db;

  Future<int> saveCategory({int? id, required String name}) async {
    if (id == null) {
      return _db.into(_db.expenseCategories).insert(
            ExpenseCategoriesCompanion.insert(name: name),
          );
    }
    await (_db.update(_db.expenseCategories)..where((c) => c.id.equals(id)))
        .write(ExpenseCategoriesCompanion(name: Value(name)));
    return id;
  }

  Future<void> setCategoryActive(int id, bool active) async {
    await (_db.update(_db.expenseCategories)..where((c) => c.id.equals(id)))
        .write(ExpenseCategoriesCompanion(isActive: Value(active)));
  }

  /// Registra un gasto y automáticamente descuenta la caja (efectivo).
  Future<void> addExpense({
    required int categoryId,
    required String description,
    required int amount,
    String note = '',
  }) async {
    await _db.transaction(() async {
      final expenseId = await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              categoryId: categoryId,
              description: Value(description),
              amount: amount,
              note: Value(note),
            ),
          );

      await _db.into(_db.cashMovements).insert(
            CashMovementsCompanion.insert(
              type: 'EXPENSE',
              amount: -amount,
              detail: Value(description),
              refType: 'EXPENSE',
              refId: expenseId,
            ),
          );
    });
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(databaseProvider));
});
