import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'database.dart';

/// Ruta del archivo real de la base de datos — el mismo que usa
/// AppDatabase internamente (ver database.dart _openConnection).
Future<String> liveDatabasePath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return p.join(dbFolder.path, 'muebles_andres.sqlite');
}

String _timestamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

/// Crea una copia consistente de la base de datos — aunque la app la
/// tenga abierta en ese momento — usando VACUUM INTO (la forma segura de
/// SQLite de sacar una foto completa sin dañar nada), y la comparte por
/// WhatsApp/Drive/correo/lo que el dueño elija. Esto es lo que evita que
/// se pierda información: se hace un respaldo ANTES de instalar una
/// actualización, y si algo sale mal al instalar, se restaura desde ahí.
Future<String> shareBackup(AppDatabase db) async {
  final tempDir = await getTemporaryDirectory();
  final backupPath = p.join(tempDir.path, 'MueblesAndres_backup_${_timestamp()}.sqlite');

  final existing = File(backupPath);
  if (await existing.exists()) await existing.delete();

  await db.customStatement("VACUUM INTO '${backupPath.replaceAll("'", "''")}'");

  await Share.shareXFiles(
    [XFile(backupPath)],
    text: 'Copia de seguridad Muebles Andrés',
    subject: 'Copia de seguridad Muebles Andrés',
  );
  return backupPath;
}

class RestoreResult {
  const RestoreResult.ok({this.safetyBackupPath}) : error = null;
  const RestoreResult.error(this.error) : safetyBackupPath = null;
  final String? error;

  /// Copia de lo que había antes de restaurar (por si se eligió mal).
  final String? safetyBackupPath;
  bool get success => error == null;
}

/// Tablas que debe tener un archivo para aceptarse como copia de esta app.
const _requiredTables = {'sales', 'product_lots', 'cash_movements'};

/// Revisa, abriendo el archivo en SOLO LECTURA, que sea una copia de
/// seguridad de esta app que se pueda restaurar. Devuelve el motivo si no
/// lo es, o null si está bien.
String? validateBackupFile(String path, {required int currentSchemaVersion}) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() < 100) {
    return 'Ese archivo no es una copia de seguridad válida.';
  }
  final raf = file.openSync();
  final header = String.fromCharCodes(raf.readSync(16));
  raf.closeSync();
  if (!header.startsWith('SQLite format 3')) {
    return 'Ese archivo no es una copia de seguridad válida (no es un .sqlite).';
  }

  sqlite.Database? db;
  try {
    db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    final check = db.select('PRAGMA quick_check').first.values.first;
    if (check != 'ok') {
      return 'La copia está dañada ($check).';
    }
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((r) => r['name'] as String)
        .toSet();
    if (!tables.containsAll(_requiredTables)) {
      return 'Ese archivo no es una copia de seguridad de esta app '
          '(le faltan: ${_requiredTables.difference(tables).join(', ')}).';
    }
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > currentSchemaVersion) {
      return 'Esa copia es de una versión más nueva de la app (v$version). '
          'Actualiza la app antes de restaurarla.';
    }
    return null;
  } on sqlite.SqliteException catch (e) {
    return 'No se pudo leer la copia: ${e.message}';
  } finally {
    db?.close();
  }
}

/// Restaura la copia [pickedPath] sobre la base [livePath]:
/// 1. valida el archivo en solo lectura (no toca nada si no sirve);
/// 2. guarda una copia de lo que hay ahora con VACUUM INTO
///    `antes_de_restaurar_<fecha>.sqlite` (junto a la base);
/// 3. copia el archivo elegido a un temporal y, ya completo, lo pone en
///    lugar de la base (si la copia falla a la mitad, la base no se toca).
/// Después la app se debe cerrar: la conexión [db] queda cerrada.
Future<RestoreResult> restoreFromFile(
  AppDatabase db,
  String pickedPath, {
  required String livePath,
}) async {
  final error = validateBackupFile(pickedPath, currentSchemaVersion: db.schemaVersion);
  if (error != null) return RestoreResult.error(error);

  final safety = p.join(p.dirname(livePath), 'antes_de_restaurar_${_timestamp()}.sqlite');
  final safetyFile = File(safety);
  if (await safetyFile.exists()) await safetyFile.delete();
  await db.customStatement("VACUUM INTO '${safety.replaceAll("'", "''")}'");

  final temp = File('$livePath.restaurando');
  if (await temp.exists()) await temp.delete();
  await File(pickedPath).copy(temp.path);

  await db.close();
  for (final suffix in ['-journal', '-wal', '-shm']) {
    final f = File('$livePath$suffix');
    if (await f.exists()) await f.delete();
  }
  final live = File(livePath);
  if (await live.exists()) await live.delete();
  await temp.rename(livePath);
  return RestoreResult.ok(safetyBackupPath: safety);
}

/// Deja elegir un archivo .sqlite ya compartido antes y reemplaza la base
/// de datos actual con él (ver [restoreFromFile]). Después de esto la app
/// debe cerrarse y volver a abrirse.
Future<RestoreResult> restoreBackup(AppDatabase db) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final pickedPath = result?.files.single.path;
  if (pickedPath == null) {
    return const RestoreResult.error('No se eligió ningún archivo.');
  }
  return restoreFromFile(db, pickedPath, livePath: await liveDatabasePath());
}
