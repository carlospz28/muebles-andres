import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';

/// Login básico de un solo usuario: no hay roles ni multiusuario, solo una
/// puerta de entrada para que nadie más abra la app en la tablet.
class AuthService {
  AuthService(this._db);

  final AppDatabase _db;

  static String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  Future<AppUserData?> _getUser() async {
    return _db.select(_db.appUser).getSingleOrNull();
  }

  Future<bool> hasUser() async => (await _getUser()) != null;

  /// Configuración inicial: crea el único usuario de la app y la bodega
  /// principal (esta app es para un solo almacén local en la tablet).
  Future<void> createUser({
    required String username,
    required String password,
    String storeName = '',
  }) async {
    final salt = _randomSalt();
    final hash = _hash(password, salt);
    await _db.into(_db.appUser).insert(
          AppUserCompanion.insert(
            username: username,
            passwordHash: '$salt\$$hash',
            storeName: Value(storeName),
          ),
        );

    final existingWarehouse = await _db.select(_db.warehouses).getSingleOrNull();
    if (existingWarehouse == null) {
      await _db.into(_db.warehouses).insert(
            WarehousesCompanion.insert(
              name: storeName.isEmpty ? 'Principal' : storeName,
            ),
          );
    }
  }

  Future<bool> verifyLogin(String username, String password) async {
    final user = await _getUser();
    if (user == null) return false;
    if (user.username != username) return false;

    final parts = user.passwordHash.split('\$');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final storedHash = parts[1];
    return _hash(password, salt) == storedHash;
  }

  Future<void> changePassword(String newPassword) async {
    final user = await _getUser();
    if (user == null) return;
    final salt = _randomSalt();
    final hash = _hash(newPassword, salt);
    await (_db.update(_db.appUser)..where((u) => u.id.equals(user.id)))
        .write(AppUserCompanion(passwordHash: Value('$salt\$$hash')));
  }
}
