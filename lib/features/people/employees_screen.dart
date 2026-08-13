import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'people_providers.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, {Employee? employee}) {
    final nameCtrl = TextEditingController(text: employee?.name ?? '');
    final docCtrl = TextEditingController(text: employee?.document ?? '');
    final rateCtrl = TextEditingController(
      text: employee == null || employee.defaultCommissionRate == 0
          ? ''
          : employee.defaultCommissionRate.toString(),
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(employee == null ? 'Nuevo vendedor' : 'Editar vendedor'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: docCtrl,
                decoration: const InputDecoration(labelText: 'Documento (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Comisión predeterminada (%)',
                  helperText: 'Se aplica sola al asignarlo a una venta o abono. '
                      'Se puede ajustar caso por caso ahí mismo.',
                  suffixText: '%',
                ),
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
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(peopleRepositoryProvider).saveEmployee(
                    id: employee?.id,
                    name: name,
                    document: docCtrl.text.trim().isEmpty ? null : docCtrl.text.trim(),
                    defaultCommissionRate: double.tryParse(rateCtrl.text.trim()) ?? 0,
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
    final employeesAsync = ref.watch(employeesStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo vendedor'),
      ),
      body: employeesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (employees) {
          if (employees.isEmpty) {
            return const Center(child: Text('No hay vendedores registrados.'));
          }
          return ListView.separated(
            itemCount: employees.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = employees[i];
              return ListTile(
                title: Text(e.name),
                subtitle: Text([
                  if ((e.document ?? '').isNotEmpty) e.document!,
                  if (e.defaultCommissionRate != 0)
                    'Comisión: ${e.defaultCommissionRate.toStringAsFixed(1)}%',
                ].join(' · ')),
                onTap: () => _openForm(context, ref, employee: e),
                trailing: Switch(
                  value: e.isActive,
                  onChanged: (v) =>
                      ref.read(peopleRepositoryProvider).setEmployeeActive(e.id, v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
