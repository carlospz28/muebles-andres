import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/features/cash/cash_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> cashMove(int amount, DateTime at, {String type = 'SALE', String method = 'CASH'}) =>
      db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
            type: type,
            amount: amount,
            method: Value(method),
            refType: type,
            refId: 1,
            date: Value(at),
          ));

  test('#1 ajuste a las 15 después de una venta de contado a las 10: caja = lo contado', () async {
    await cashMove(100000, DateTime(2026, 10, 28, 10));
    await CashRepository(db).setOpeningCash(date: DateTime(2026, 10, 28, 15), amount: 100000);
    expect((await loadCashAvailable(db)).amount, 100000);

    // Lo que entra después del conteo sí se suma.
    await cashMove(50000, DateTime(2026, 10, 28, 16));
    await cashMove(-20000, DateTime(2026, 10, 28, 17), type: 'EXPENSE');
    await cashMove(70000, DateTime(2026, 10, 28, 17), method: 'CONSIGNMENT');
    expect((await loadCashAvailable(db)).amount, 130000);
  });

  test('#1 dos ajustes el mismo día: manda el último, sin error de fecha repetida', () async {
    final repo = CashRepository(db);
    await repo.setOpeningCash(date: DateTime(2026, 10, 28, 9), amount: 100000);
    await repo.setOpeningCash(date: DateTime(2026, 10, 28, 15), amount: 120000);
    // Mismo instante: actualiza la misma fila.
    await repo.setOpeningCash(date: DateTime(2026, 10, 28, 15), amount: 125000);
    expect((await db.select(db.cashSessions).get()).length, 2);
    expect((await loadCashAvailable(db)).amount, 125000);
  });

  test('#1 una base vieja guardada al inicio del día sigue funcionando igual', () async {
    await db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(date: DateTime(2026, 10, 1), openingCash: const Value(300000)));
    await cashMove(40000, DateTime(2026, 10, 1, 11));
    expect((await loadCashAvailable(db)).amount, 340000);
  });
}
