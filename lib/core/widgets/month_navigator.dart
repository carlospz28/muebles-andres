import 'package:flutter/material.dart';

const monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Rango [inicio, fin) del mes dado (día 1 a día 1 del siguiente).
(DateTime, DateTime) monthRange(DateTime month) {
  return (
    DateTime(month.year, month.month, 1),
    DateTime(month.year, month.month + 1, 1),
  );
}

/// Flechas para moverse mes a mes — para poder revisar cualquier mes
/// anterior, no solo el actual.
class MonthNavigator extends StatelessWidget {
  const MonthNavigator({super.key, required this.month, required this.onChanged});

  /// Día 1 del mes seleccionado.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1, 1)),
        ),
        Text(
          '${monthNames[month.month - 1]} ${month.year}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: () => onChanged(DateTime(month.year, month.month + 1, 1)),
        ),
      ],
    );
  }
}
