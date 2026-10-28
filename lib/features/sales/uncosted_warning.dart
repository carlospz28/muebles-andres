import 'package:flutter/material.dart';

import 'sales_providers.dart';

/// Avisa que salieron unidades sin inventario registrado (y con qué costo
/// se registraron), para que el dueño ingrese la compra que falta.
Future<void> showUncostedWarning(BuildContext context, List<UncostedUnits> warnings) async {
  if (warnings.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
      title: const Text('Se vendió sin inventario registrado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in warnings) ...[
            Text('• ${w.message}'),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 4),
          const Text('La existencia de esos productos queda en negativo hasta que se ingrese.'),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
      ],
    ),
  );
}
