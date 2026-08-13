import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import 'people_providers.dart';

/// Diálogo para elegir un cliente escribiendo su nombre, o crearlo al
/// vuelo si no existe — así no hay que pasar primero por el módulo de
/// Clientes para poder vender (el cliente puede ser distinto cada vez).
Future<Customer?> pickOrCreateCustomerDialog(BuildContext context, WidgetRef ref) async {
  final customers = await ref.read(customersStreamProvider.future);
  if (!context.mounted) return null;

  var search = '';
  final searchCtrl = TextEditingController();

  return showDialog<Customer>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final query = search.trim().toLowerCase();
        final filtered = query.isEmpty
            ? customers
            : customers.where((c) => c.name.toLowerCase().contains(query)).toList();
        final exactMatch = customers.any((c) => c.name.toLowerCase() == query);

        return AlertDialog(
          title: const Text('Cliente'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Escribe el nombre del cliente...',
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: query.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              customers.isEmpty
                                  ? 'Escribe un nombre para crear el primer cliente.'
                                  : 'Escribe el nombre para buscarlo o crear uno nuevo.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            if (!exactMatch)
                              ListTile(
                                leading: const Icon(Icons.person_add_alt),
                                title: Text('Crear cliente "${searchCtrl.text.trim()}"'),
                                onTap: () async {
                                  final db = ref.read(databaseProvider);
                                  final id = await ref
                                      .read(peopleRepositoryProvider)
                                      .saveCustomer(name: searchCtrl.text.trim());
                                  final created = await (db.select(db.customers)
                                        ..where((c) => c.id.equals(id)))
                                      .getSingle();
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext, created);
                                  }
                                },
                              ),
                            for (final c in filtered)
                              ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(c.name),
                                subtitle:
                                    (c.phone ?? '').isNotEmpty ? Text(c.phone!) : null,
                                onTap: () => Navigator.pop(dialogContext, c),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    ),
  );
}
