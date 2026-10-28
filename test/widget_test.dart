import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:muebles_andres/app.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/providers.dart';

void main() {
  testWidgets('App arranca y muestra la puerta de autenticación',
      (WidgetTester tester) async {
    // La app NUNCA debe abrir la base real (Documentos\muebles_andres.sqlite)
    // desde una prueba: se reemplaza por una base en memoria.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MueblesAndresApp(),
      ),
    );
    await tester.pump();

    // No debe lanzar excepciones al construir el árbol inicial.
    expect(tester.takeException(), isNull);
  });
}
