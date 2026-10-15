import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kit_form_screen.dart';
import 'kits_providers.dart';

class KitsScreen extends ConsumerWidget {
  const KitsScreen({super.key});

  Future<void> _createKit(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo kit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre (ej: Comedor 6 puestos)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    final kitId = await ref.read(kitsRepositoryProvider).saveKit(
          name: name,
          description: descCtrl.text.trim(),
        );

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KitFormScreen(kitId: kitId)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitsAsync = ref.watch(kitsStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'kits',
        onPressed: () => _createKit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo kit'),
      ),
      body: kitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (kits) {
          if (kits.isEmpty) {
            return const Center(
              child: Text('Aún no hay kits (ej: comedores, salas).'),
            );
          }
          return ListView.separated(
            itemCount: kits.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final k = kits[i];
              return ListTile(
                title: Text(k.name),
                subtitle: Text(k.description),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => KitFormScreen(kitId: k.id)),
                ),
                trailing: Switch(
                  value: k.isActive,
                  onChanged: (v) => ref.read(kitsRepositoryProvider).setKitActive(k.id, v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
