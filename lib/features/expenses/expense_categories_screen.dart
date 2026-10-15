import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'expenses_providers.dart';

class ExpenseCategoriesScreen extends ConsumerWidget {
  const ExpenseCategoriesScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {ExpenseCategory? category}) {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Nueva categoría de gasto' : 'Editar categoría'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref
                  .read(expensesRepositoryProvider)
                  .saveCategory(id: category?.id, name: name);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(expenseCategoriesStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expenseCategories',
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No hay categorías de gasto.'));
          }
          return ListView.separated(
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = categories[i];
              return ListTile(
                title: Text(c.name),
                onTap: () => _openForm(context, ref, category: c),
                trailing: Switch(
                  value: c.isActive,
                  onChanged: (v) =>
                      ref.read(expensesRepositoryProvider).setCategoryActive(c.id, v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
