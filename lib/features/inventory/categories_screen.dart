import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'catalog_providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {Category? category}) {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Nueva categoría' : 'Editar categoría'),
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
              await ref.read(catalogRepositoryProvider).saveCategory(
                    id: category?.id,
                    name: name,
                  );
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
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'categories',
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('Aún no hay categorías.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = categories[i];
              return ListTile(
                title: Text(c.name),
                subtitle: Text(c.isActive ? 'Activa' : 'Inactiva'),
                onTap: () => _openForm(context, ref, category: c),
                trailing: Switch(
                  value: c.isActive,
                  onChanged: (v) => ref
                      .read(catalogRepositoryProvider)
                      .setCategoryActive(c.id, v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
