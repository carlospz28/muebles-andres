import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

class CashRepository {
  CashRepository(this._db);
  final AppDatabase _db;

  /// Registra o actualiza la base de caja. No es un valor "del día" que
  /// haya que repetir a diario: se guarda con la fecha de hoy como punto
  /// de partida y de ahí en adelante el sistema solo le va sumando/
  /// restando cada movimiento de efectivo, sin reiniciarse nunca solo.
  Future<void> setOpeningCash({
    required DateTime date,
    required int amount,
    String notes = '',
  }) async {
    final normalized = _startOfDay(date);
    await _db.into(_db.cashSessions).insertOnConflictUpdate(
          CashSessionsCompanion.insert(
            date: normalized,
            openingCash: Value(amount),
            notes: Value(notes),
          ),
        );
  }
}

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  return CashRepository(ref.watch(databaseProvider));
});
