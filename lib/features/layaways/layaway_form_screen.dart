import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/pdf/receipt_pdf.dart';
import '../../core/providers.dart';
import '../inventory/catalog_providers.dart';
import '../kits/kit_picker_dialog.dart';
import '../sales/payment_dialog.dart';
import 'layaways_providers.dart';

class LayawayFormScreen extends ConsumerWidget {
  const LayawayFormScreen({super.key, required this.layawayId});

  final int layawayId;

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final products = await ref.read(productsStreamProvider.future);
    if (!context.mounted) return;

    Product? selected;
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    var search = '';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final filtered = search.isEmpty
              ? products
              : products
                  .where((p) =>
                      p.name.toLowerCase().contains(search.toLowerCase()) ||
                      p.sku.contains(search))
                  .toList();

          return AlertDialog(
            title: const Text('Agregar producto'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected == null) ...[
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar producto...',
                      ),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final p = filtered[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            'SKU ${p.sku} · ${formatCopWithSymbol(p.price)}',
                          ),
                          onTap: () => setState(() {
                            selected = p;
                            priceCtrl.text = formatCop(p.price);
                          }),
                        );
                      },
                    ),
                  ] else ...[
                    ListTile(
                      title: Text(selected!.name),
                      subtitle: Text('SKU ${selected!.sku}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => selected = null),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Precio de venta',
                        prefixText: '\$ ',
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              if (selected != null)
                FilledButton(
                  onPressed: () async {
                    final qty = int.tryParse(qtyCtrl.text) ?? 0;
                    final price = ThousandsInputFormatter.parse(priceCtrl.text);
                    if (qty <= 0 || price <= 0) return;
                    try {
                      final shortage = await ref.read(layawaysRepositoryProvider).addItem(
                            layawayId: layawayId,
                            productId: selected!.id,
                            quantity: qty,
                            unitPrice: price,
                          );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (shortage > 0 && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Aviso: faltan $shortage unidades en inventario para '
                              'completar este apartado.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: const Text('Agregar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addKit(BuildContext context, WidgetRef ref) async {
    final picked = await showKitPickerDialog(context, ref);
    if (picked == null) return;

    var totalShortage = 0;
    for (final item in picked.items) {
      try {
        totalShortage += await ref.read(layawaysRepositoryProvider).addItem(
              layawayId: layawayId,
              productId: item.productId,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              discount: item.discount,
              kitId: picked.kitId,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
    if (totalShortage > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aviso: faltan $totalShortage unidades en inventario para completar '
            'este apartado.',
          ),
        ),
      );
    }
  }

  Future<void> _addPayment(
    BuildContext context,
    WidgetRef ref,
    int balance,
    int? employeeId,
  ) async {
    final result = await showPaymentDialog(
      context,
      totalToPay: balance,
      title: 'Registrar abono',
      allowPartial: true,
      showSupplierOption: true,
    );
    if (result == null) return;
    if (!context.mounted) return;

    var defaultRate = 0.0;
    if (employeeId != null) {
      final db = ref.read(databaseProvider);
      final employee =
          await (db.select(db.employees)..where((e) => e.id.equals(employeeId)))
              .getSingleOrNull();
      defaultRate = employee?.defaultCommissionRate ?? 0;
    }

    final rateCtrl = TextEditingController(
      text: defaultRate == 0 ? '' : defaultRate.toString(),
    );
    if (!context.mounted) return;
    final rate = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comisión sobre este abono'),
        content: TextField(
          controller: rateCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Porcentaje (%)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('Sin comisión'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(rateCtrl.text) ?? 0),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    await ref.read(layawaysRepositoryProvider).addPayment(
          layawayId: layawayId,
          paymentLines: result.lines,
          commissionRate: rate ?? 0,
        );
  }

  Future<void> _invoice(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(layawaysRepositoryProvider).invoiceToSale(layawayId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Apartado facturado. Actívalo como "Entregado al cliente" cuando '
              'reciba el mueble — ahí se descuenta el inventario.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _cancelWithoutInvoice(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(layawaysRepositoryProvider).cancelWithoutInvoice(layawayId);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _returnLayaway(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Devolver apartado'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonCtrl.text.trim()),
            child: const Text('Confirmar devolución'),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      await ref
          .read(layawaysRepositoryProvider)
          .returnLayaway(layawayId: layawayId, reason: reason);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref, Layaway layaway) async {
    final db = ref.read(databaseProvider);

    final customer =
        await (db.select(db.customers)..where((c) => c.id.equals(layaway.customerId)))
            .getSingle();
    final user = await db.select(db.appUser).getSingleOrNull();

    final itemViews = await ref.read(layawayItemsProvider(layawayId).future);
    final totals = await ref.read(layawayTotalsProvider(layawayId).future);

    final payments = await (db.select(db.payments)
          ..where((p) => p.layawayId.equals(layawayId)))
        .get();
    final paymentLines = <ReceiptPaymentLine>[];
    for (final p in payments) {
      final lines = await (db.select(db.paymentLines)
            ..where((l) => l.paymentId.equals(p.id)))
          .get();
      for (final l in lines) {
        paymentLines.add(ReceiptPaymentLine(
          label: l.method == 'CASH'
              ? 'Efectivo'
              : l.method == 'SUPPLIER'
                  ? 'Proveedores'
                  : 'Consignación',
          amount: l.amount,
        ));
      }
    }

    await shareLayawayReceipt(
      storeName: user?.storeName ?? '',
      layawayId: layawayId,
      date: layaway.date,
      customerName: customer.name,
      items: [
        for (final v in itemViews)
          ReceiptLine(
            productName: v.productName,
            quantity: v.item.quantity,
            unitPrice: v.item.unitPrice,
            lineTotal: v.item.lineTotal,
          ),
      ],
      total: totals.total,
      paid: totals.paid,
      balance: totals.balance,
      payments: paymentLines,
      delivered: layaway.delivered,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layawayAsync = ref.watch(layawayByIdProvider(layawayId));
    final itemsAsync = ref.watch(layawayItemsProvider(layawayId));
    final totalsAsync = ref.watch(layawayTotalsProvider(layawayId));
    final paymentsAsync = ref.watch(layawayPaymentsProvider(layawayId));

    return Scaffold(
      appBar: AppBar(title: Text('Apartado #$layawayId')),
      body: layawayAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (layaway) {
          final inProcess = layaway.state == 'IN_PROCESS';
          final totals = totalsAsync.value;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Productos', style: Theme.of(context).textTheme.titleMedium),
                  Chip(label: Text(layaway.state)),
                ],
              ),
              itemsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, st) => Text('Error: $e'),
                data: (items) => Column(
                  children: [
                    for (final v in items)
                      ListTile(
                        title: Text(v.productName),
                        subtitle: Text(
                          '${v.item.quantity} x ${formatCopWithSymbol(v.item.unitPrice)}',
                        ),
                        trailing: inProcess
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(layawaysRepositoryProvider)
                                    .removeItem(v.item.id),
                              )
                            : Text(formatCopWithSymbol(v.item.lineTotal)),
                      ),
                  ],
                ),
              ),
              if (inProcess)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addItem(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Producto'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addKit(context, ref),
                        icon: const Icon(Icons.weekend_outlined),
                        label: const Text('Kit'),
                      ),
                    ),
                  ],
                ),
              const Divider(height: 32),
              if (totals != null) ...[
                _TotalsRow(label: 'Total', value: totals.total),
                if (layaway.state == 'IN_PROCESS' || layaway.state == 'INVOICED') ...[
                  _TotalsRow(label: 'Pagado', value: totals.paid),
                  _TotalsRow(label: 'Saldo', value: totals.balance, bold: true),
                ] else
                  // Devuelto o cancelado: lo abonado ya se le devolvió.
                  _TotalsRow(label: 'Pagado (neto, tras la devolución)', value: totals.paid),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Entregado al cliente'),
                  subtitle: Text(
                    layaway.state == 'RETURNED'
                        ? 'La venta de este apartado se devolvió: no se entrega.'
                        : layaway.state != 'INVOICED'
                        ? 'Se activa cuando el apartado ya esté facturado (saldo en \$0).'
                        : layaway.delivered
                            ? 'Inventario ya descontado.'
                            : 'Puede terminar de pagar y reclamar el mueble días después. '
                                'Al activarlo se descuenta el inventario real.',
                  ),
                  value: layaway.delivered,
                  onChanged: (layaway.state == 'INVOICED' && !layaway.delivered)
                      ? (v) => ref.read(layawaysRepositoryProvider).setDelivered(layawayId, v)
                      : null,
                ),
                const SizedBox(height: 16),
                Text('Historial de abonos', style: Theme.of(context).textTheme.titleMedium),
                paymentsAsync.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, st) => Text('Error: $e'),
                  data: (payments) => Column(
                    children: [
                      for (final p in payments)
                        ListTile(
                          leading: Icon(p.totalAmount < 0 ? Icons.undo : Icons.payments_outlined),
                          title: Text(p.totalAmount < 0
                              ? 'Devolución · ${formatCopWithSymbol(-p.totalAmount)}'
                              : formatCopWithSymbol(p.totalAmount)),
                          subtitle: Text(
                            p.totalAmount < 0
                                ? 'Se devolvió por las mismas formas de pago'
                                : 'Comisión ${p.commissionRate.toStringAsFixed(1)}%: '
                                    '${formatCopWithSymbol(p.commissionAmount)}',
                          ),
                          trailing: Text(
                            '${p.date.day}/${p.date.month}/${p.date.year}',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _exportPdf(context, ref, layaway),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Descargar / compartir PDF'),
                ),
                const SizedBox(height: 8),
                if (inProcess) ...[
                  if (totals.balance > 0)
                    FilledButton.icon(
                      onPressed: () =>
                          _addPayment(context, ref, totals.balance, layaway.employeeId),
                      icon: const Icon(Icons.add_card),
                      label: const Text('Registrar abono'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => _invoice(context, ref),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Facturar (saldo en cero)'),
                    ),
                  const SizedBox(height: 8),
                  if (totals.paid == 0)
                    OutlinedButton.icon(
                      onPressed: () => _cancelWithoutInvoice(context, ref),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar sin facturar'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _returnLayaway(context, ref),
                      icon: const Icon(Icons.undo),
                      label: const Text('Devolver apartado'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatCopWithSymbol(value), style: style),
        ],
      ),
    );
  }
}
