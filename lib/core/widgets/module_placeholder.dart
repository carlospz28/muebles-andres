import 'package:flutter/material.dart';

/// Placeholder temporal para módulos que aún no se han construido.
/// Se reemplaza módulo por módulo por la pantalla real.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Este módulo se construye en el siguiente paso.'),
        ],
      ),
    );
  }
}
