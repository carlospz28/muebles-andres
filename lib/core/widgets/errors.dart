import 'package:flutter/material.dart';

/// Texto amigable de un error de validación de los repositorios (quita el
/// "Bad state:" / "Invalid argument(s):" que agrega Dart).
String friendlyError(Object e) {
  if (e is StateError) return e.message;
  if (e is ArgumentError) return '${e.message}';
  if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
  return '$e';
}

void showErrorSnack(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
}

/// Ejecuta [action] y, si el repositorio rechaza la operación, muestra el
/// motivo en vez de dejar que la app falle. Devuelve true si salió bien.
Future<bool> runOrShowError(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return false;
  }
}

/// Validaciones comunes de los repositorios.
void checkLine({required int quantity, required int unitPrice, required int discount}) {
  if (quantity <= 0) throw StateError('La cantidad debe ser mayor que cero.');
  if (unitPrice < 0) throw StateError('El precio no puede ser negativo.');
  if (discount < 0) throw StateError('El descuento no puede ser negativo.');
  if (discount > quantity * unitPrice) {
    throw StateError('El descuento no puede ser mayor que el valor de la línea.');
  }
}

void checkRate(double rate) {
  if (rate.isNaN || rate < 0 || rate > 100) {
    throw StateError('El porcentaje de comisión debe estar entre 0 y 100.');
  }
}
