import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _copFormat = NumberFormat.decimalPattern('es_CO');

/// Formatea un entero de pesos colombianos con separador de miles.
/// Ej: 1234567 -> "1.234.567"
String formatCop(int amount) => _copFormat.format(amount);

String formatCopWithSymbol(int amount) => '\$ ${formatCop(amount)}';

/// TextInputFormatter que coloca el separador de miles automáticamente
/// mientras el usuario digita un valor en pesos (sin decimales), tal como
/// pidió el cliente: "que los puntos se coloquen automáticamente para
/// saber bien qué precio estoy colocando".
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final value = int.parse(digitsOnly);
    final formatted = formatCop(value);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Convierte el texto ya formateado ("1.234.567") de vuelta a int.
  static int parse(String formatted) {
    final digitsOnly = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return 0;
    return int.parse(digitsOnly);
  }
}
