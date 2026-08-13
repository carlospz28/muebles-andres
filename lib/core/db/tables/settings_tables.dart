import 'package:drift/drift.dart';

/// Configuración de un solo usuario (login básico, sin roles ni multiusuario).
/// Se espera una única fila (id = 1).
class AppUser extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 1, max: 60)();

  /// Hash SHA-256 de la contraseña (nunca se guarda en texto plano).
  TextColumn get passwordHash => text()();
  TextColumn get storeName => text().withDefault(const Constant(''))();
}
