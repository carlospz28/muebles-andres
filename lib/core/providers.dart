import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_service.dart';
import 'db/database.dart';

/// Instancia única de la base de datos para toda la app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(databaseProvider));
});

/// true mientras haya una sesión iniciada. Al reiniciar la app siempre
/// vuelve a false (se pide login cada vez que se abre, como pidió el
/// cliente: "un login muy básico, solo para un usuario").
final isLoggedInProvider = StateProvider<bool>((ref) => false);

/// Esta app es para un solo almacén local: en vez de pedir elegir bodega
/// en cada pantalla, todo el negocio opera contra la única bodega creada
/// en la configuración inicial.
final defaultWarehouseProvider = FutureProvider<Warehouse>((ref) async {
  final db = ref.watch(databaseProvider);
  final existing = await db.select(db.warehouses).getSingleOrNull();
  if (existing != null) return existing;

  final id = await db.into(db.warehouses).insert(
        const WarehousesCompanion(name: Value('Principal')),
      );
  return (db.select(db.warehouses)..where((w) => w.id.equals(id))).getSingle();
});
