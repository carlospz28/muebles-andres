import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/backup_service.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// #7 Restaurar. Trabaja con archivos en una carpeta temporal del sistema
/// (nunca con la base real), porque lo que se prueba es reemplazar un
/// archivo por otro.
void main() {
  late Directory dir;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('restaurar_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Crea una base de la app con un producto llamado [productName].
  Future<String> makeAppDb(String name, String productName) async {
    final path = p.join(dir.path, name);
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    final cat = await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Salas'));
    await db.into(db.products).insert(ProductsCompanion.insert(sku: '0001', name: productName, categoryId: cat));
    await db.close();
    return path;
  }

  Future<List<String>> productNames(String path) async {
    final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    final names = db.select('SELECT name FROM products').map((r) => r['name'] as String).toList();
    db.close();
    return names;
  }

  test('restaura una copia válida y guarda antes una copia de lo que había', () async {
    final live = await makeAppDb('muebles_andres.sqlite', 'Sofá ACTUAL');
    final backup = await makeAppDb('copia.sqlite', 'Comedor RESPALDO');

    final db = AppDatabase.forTesting(NativeDatabase(File(live)));
    final result = await restoreFromFile(db, backup, livePath: live);

    expect(result.success, isTrue, reason: result.error);
    expect(await productNames(live), ['Comedor RESPALDO']);
    expect(p.basename(result.safetyBackupPath!), startsWith('antes_de_restaurar_'));
    expect(await productNames(result.safetyBackupPath!), ['Sofá ACTUAL']);
    expect(File('$live.restaurando').existsSync(), isFalse);
  });

  test('rechaza un archivo que no es SQLite y no toca la base', () async {
    final live = await makeAppDb('muebles_andres.sqlite', 'Sofá ACTUAL');
    final bad = p.join(dir.path, 'foto.sqlite');
    File(bad).writeAsStringSync('esto no es una base de datos' * 10);

    final db = AppDatabase.forTesting(NativeDatabase(File(live)));
    final result = await restoreFromFile(db, bad, livePath: live);
    await db.close();

    expect(result.success, isFalse);
    expect(await productNames(live), ['Sofá ACTUAL']);
    expect(dir.listSync().where((f) => p.basename(f.path).startsWith('antes_de_restaurar_')), isEmpty);
  });

  test('rechaza una base SQLite de otra app (le faltan tablas)', () async {
    final other = p.join(dir.path, 'esqueletera_omar.sqlite');
    final o = sqlite.sqlite3.open(other);
    o.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY); INSERT INTO orders VALUES (1);');
    o.close();

    final error = validateBackupFile(other, currentSchemaVersion: 8);
    expect(error, contains('no es una copia de seguridad de esta app'));
  });

  test('rechaza una copia de una versión más nueva de la app', () async {
    final newer = await makeAppDb('nueva.sqlite', 'X');
    final n = sqlite.sqlite3.open(newer);
    n.execute('PRAGMA user_version = 99');
    n.close();

    expect(validateBackupFile(newer, currentSchemaVersion: 8), contains('más nueva'));
    expect(validateBackupFile(newer, currentSchemaVersion: 99), isNull);
  });
}
