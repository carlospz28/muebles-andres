import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

class CashRepository {
  CashRepository(this._db);
  final AppDatabase _db;

  /// Registra la base de caja: cuánto efectivo había en el momento [date]
  /// (normalmente un conteo físico "ahora"). Se guarda con la HORA REAL,
  /// no al inicio del día: así la caja solo suma lo que se mueva DESPUÉS
  /// del conteo, y no vuelve a sumar las ventas de esa misma mañana que ya
  /// estaban dentro del efectivo contado. Nunca se reinicia solo.
  Future<void> setOpeningCash({
    required DateTime date,
    required int amount,
    String notes = '',
  }) async {
    // `date` es única: si se ajusta dos veces en el mismo instante se
    // actualiza esa fila (insertOnConflictUpdate solo miraba el id y
    // fallaba con "UNIQUE constraint failed: cash_sessions.date").
    await _db.into(_db.cashSessions).insert(
          CashSessionsCompanion.insert(
            date: date,
            openingCash: Value(amount),
            notes: Value(notes),
          ),
          onConflict: DoUpdate(
            (_) => CashSessionsCompanion(openingCash: Value(amount), notes: Value(notes)),
            target: [_db.cashSessions.date],
          ),
        );
  }
}

class CashAvailable {
  const CashAvailable(this.openingCash, this.baseDate, this.amount);

  /// Última base de caja registrada (0 si nunca se ha registrado).
  final int openingCash;
  final DateTime? baseDate;

  /// Efectivo disponible: la base más todo el efectivo movido desde ella.
  final int amount;
}

/// Caja disponible (efectivo) — regla única que usa Inicio: la última base
/// registrada más todo movimiento en efectivo con fecha igual o posterior
/// a esa base. Las bases viejas guardadas al inicio del día siguen
/// funcionando igual.
Future<CashAvailable> loadCashAvailable(AppDatabase db) async {
  final session = await (db.select(db.cashSessions)
        ..orderBy([(s) => OrderingTerm.desc(s.date)])
        ..limit(1))
      .getSingleOrNull();
  final since = session?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
  final row = await (db.selectOnly(db.cashMovements)
        ..addColumns([db.cashMovements.amount.sum()])
        ..where(db.cashMovements.method.equals('CASH') &
            db.cashMovements.date.isBiggerOrEqualValue(since)))
      .getSingle();
  final base = session?.openingCash ?? 0;
  return CashAvailable(base, session?.date, base + (row.read(db.cashMovements.amount.sum()) ?? 0));
}

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  return CashRepository(ref.watch(databaseProvider));
});
