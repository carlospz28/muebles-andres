import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../people/customer_picker_dialog.dart';
import '../people/people_providers.dart';
import 'production_providers.dart';

String _fmtDate(DateTime? d) => d == null ? 'Sin definir' : '${d.day}/${d.month}/${d.year}';

class ProductionFormScreen extends ConsumerWidget {
  const ProductionFormScreen({super.key, required this.orderId});

  final int orderId;

  Future<void> _editProductType(
      BuildContext context, WidgetRef ref, ProductionOrder order) async {
    final ctrl = TextEditingController(text: order.productType);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tipo de mueble'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tipo de mueble / descripción'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(productionRepositoryProvider).updateOrder(
                    id: order.id,
                    productType: ctrl.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCustomer(
      BuildContext context, WidgetRef ref, ProductionOrder order) async {
    final customer = await pickOrCreateCustomerDialog(context, ref);
    if (customer == null) return;
    await ref.read(productionRepositoryProvider).updateOrder(
          id: order.id,
          customerId: Value(customer.id),
        );
  }

  Future<void> _editSalePrice(
      BuildContext context, WidgetRef ref, ProductionOrder order) async {
    final ctrl = TextEditingController(
      text: order.salePrice == 0 ? '' : formatCop(order.salePrice),
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Precio de venta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
          decoration: const InputDecoration(prefixText: '\$ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(productionRepositoryProvider).updateOrder(
                    id: order.id,
                    salePrice: Value(ThousandsInputFormatter.parse(ctrl.text)),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotes(
      BuildContext context, WidgetRef ref, ProductionOrder order) async {
    final ctrl = TextEditingController(text: order.notes);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notas'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Detalles adicionales...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(productionRepositoryProvider).updateOrder(
                    id: order.id,
                    notes: ctrl.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editStage(
      BuildContext context, WidgetRef ref, ProductionStageView view) async {
    final employees = await ref.read(activeEmployeesStreamProvider.future);
    if (!context.mounted) return;

    var completed = view.stage.completed;
    var employeeId = view.stage.responsibleEmployeeId;
    final costCtrl = TextEditingController(
      text: view.stage.laborCost == 0 ? '' : formatCop(view.stage.laborCost),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(productionStageLabel(view.stage.stage)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Completado'),
                  value: completed,
                  onChanged: (v) => setState(() => completed = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: employeeId,
                  decoration: const InputDecoration(labelText: 'Responsable'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                    for (final e in employees)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => employeeId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Costo de mano de obra',
                    prefixText: '\$ ',
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
                await ref.read(productionRepositoryProvider).updateStage(
                      stageId: view.stage.id,
                      completed: completed,
                      responsibleEmployeeId: employeeId,
                      laborCost: ThousandsInputFormatter.parse(costCtrl.text),
                    );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSetDate(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required DateTime? current,
    required Future<void> Function(DateTime) onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: title,
    );
    if (picked == null) return;
    await onPicked(picked);
  }

  Color _stateColor(String state, BuildContext context) {
    switch (state) {
      case 'DELIVERED':
        return Colors.green;
      case 'CANCELLED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'DELIVERED':
        return 'Entregado';
      case 'CANCELLED':
        return 'Cancelado';
      default:
        return 'En proceso';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(productionOrderByIdProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ficha de producción')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (order) {
          final customerAsync =
              ref.watch(productionOrderCustomerProvider(order.customerId));
          final stagesAsync = ref.watch(productionStagesProvider(order.id));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.productType.isEmpty ? '(Sin tipo de mueble)' : order.productType,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Chip(
                    label: Text(_stateLabel(order.state)),
                    backgroundColor:
                        _stateColor(order.state, context).withValues(alpha: 0.15),
                    labelStyle: TextStyle(color: _stateColor(order.state, context)),
                  ),
                ],
              ),
              if (order.saleId != null)
                Text('Vinculada a la venta #${order.saleId}',
                    style: Theme.of(context).textTheme.bodySmall)
              else if (order.layawayId != null)
                Text('Vinculada al apartado #${order.layawayId}',
                    style: Theme.of(context).textTheme.bodySmall),
              TextButton.icon(
                onPressed: () => _editProductType(context, ref, order),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar tipo de mueble'),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Cliente'),
                subtitle: Text(customerAsync.value?.name ?? 'Sin cliente'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editCustomer(context, ref, order),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Precio de venta'),
                subtitle: Text(formatCopWithSymbol(order.salePrice)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editSalePrice(context, ref, order),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Fecha de programación'),
                subtitle: Text(_fmtDate(order.scheduledDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickAndSetDate(
                  context,
                  ref,
                  title: 'Fecha de programación',
                  current: order.scheduledDate,
                  onPicked: (d) => ref.read(productionRepositoryProvider).updateOrder(
                        id: order.id,
                        scheduledDate: Value(d),
                      ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.build_outlined),
                title: const Text('Fecha de elaboración'),
                subtitle: Text(_fmtDate(order.elaborationDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickAndSetDate(
                  context,
                  ref,
                  title: 'Fecha de elaboración',
                  current: order.elaborationDate,
                  onPicked: (d) => ref.read(productionRepositoryProvider).updateOrder(
                        id: order.id,
                        elaborationDate: Value(d),
                      ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('Fecha de entrega'),
                subtitle: Text(_fmtDate(order.deliveryDate)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Notas'),
                subtitle: Text(order.notes.isEmpty ? 'Sin notas' : order.notes),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editNotes(context, ref, order),
              ),
              const Divider(),
              Text('Etapas de fabricación', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              stagesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, st) => Text('Error: $e'),
                data: (stages) {
                  final totalLabor =
                      stages.fold<int>(0, (sum, s) => sum + s.stage.laborCost);
                  return Column(
                    children: [
                      for (final s in stages)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              s.stage.completed
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: s.stage.completed ? Colors.green : null,
                            ),
                            title: Text(productionStageLabel(s.stage.stage)),
                            subtitle: Text([
                              s.employeeName ?? 'Sin responsable',
                              formatCopWithSymbol(s.stage.laborCost),
                              if (s.stage.completedDate != null)
                                _fmtDate(s.stage.completedDate),
                            ].join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _editStage(context, ref, s),
                          ),
                        ),
                      const SizedBox(height: 8),
                      ListTile(
                        title: const Text('Total mano de obra'),
                        trailing: Text(
                          formatCopWithSymbol(totalLabor),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Divider(),
              if (order.state == 'IN_PROCESS') ...[
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(productionRepositoryProvider).markDelivered(order.id),
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Marcar entregado'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(productionRepositoryProvider).cancel(order.id),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar ficha'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
