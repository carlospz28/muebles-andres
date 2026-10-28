import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muebles_andres/core/db/database.dart';
import 'package:muebles_andres/core/export/inventory_export.dart';

/// Genera el Excel de inventario a partir de una COPIA de una base real.
/// Se corre con: `INSPECT_DB=copia.sqlite flutter test test/inventory_export_test.dart`
void main() {
  final path = Platform.environment['INSPECT_DB'];

  test('genera el Excel de inventario con datos reales', () async {
    final db = AppDatabase.forTesting(NativeDatabase(File(path!)));
    final products = await db.select(db.products).get();
    final lots = await db.select(db.productLots).get();
    // ignore: avoid_print
    print('productos: ${products.length}, lotes: ${lots.length}');

    final bytes = await buildInventoryExcel(db);
    final out = File('${File(path).parent.path}${Platform.pathSeparator}Inventario_prueba.xlsx');
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Excel: ${out.path} (${bytes.length} bytes)');
    expect(bytes, isNotEmpty);
    await db.close();
  }, skip: path == null ? 'Falta INSPECT_DB' : false);
}
