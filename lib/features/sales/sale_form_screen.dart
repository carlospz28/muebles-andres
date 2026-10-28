import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/pdf/receipt_pdf.dart';
import '../../core/providers.dart';
import '../../core/widgets/errors.dart';
import '../inventory/catalog_providers.dart';
import '../kits/kit_picker_dialog.dart';
import 'payment_dialog.dart';
import 'sales_providers.dart';
import 'uncosted_warning.dart';

class SaleFormScreen extends ConsumerWidget {
  const SaleFormScreen({super.key, required this.saleId});

  final int saleId;

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final products = await ref.read(productsStreamProvider.future);
    if (!context.mounted) return;

    Product? selected;
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '0');
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Descuento (opcional)',
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
                    final discount = ThousandsInputFormatter.parse(discountCtrl.text);
                    if (qty <= 0 || price <= 0) return;
                    final ok = await runOrShowError(
                      dialogContext,
                      () => ref.read(salesRepositoryProvider).addItem(
                            saleId: saleId,
                            productId: selected!.id,
                            quantity: qty,
                            unitPrice: price,
                            discount: discount,
                          ),
                    );
                    if (ok && dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Agregar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCommission(BuildContext context, WidgetRef ref, Sale sale) async {
    final ctrl = TextEditingController(
      text: sale.commissionRate == 0 ? '' : sale.commissionRate.toString(),
    );
    final rate = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comisión de esta venta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Porcentaje (%)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text) ?? 0),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (rate == null || !context.mounted) return;
    await runOrShowError(context, () => ref.read(salesRepositoryProvider).setCommissionRate(saleId, rate));
  }

  Future<void> _addKit(BuildContext context, WidgetRef ref) async {
    final picked = await showKitPickerDialog(context, ref);
    if (picked == null) return;

    if (!context.mounted) return;
    await runOrShowError(
      context,
      () => ref.read(salesRepositoryProvider).addKitLines(
            saleId: saleId,
            kitId: picked.kitId,
            lines: [for (final i in picked.items) i.toKitLine()],
          ),
    );
  }

  Future<void> _confirmSale(BuildContext context, WidgetRef ref, Sale sale) async {
    final result = await showPaymentDialog(
      context,
      totalToPay: sale.total,
      title: 'Cobrar venta ${sale.number}',
      showDeliveredOption: true,
      showSupplierOption: true,
    );
    if (result == null) return;

    try {
      final warnings = await ref.read(salesRepositoryProvider).confirmSale(
            saleId: saleId,
            paymentLines: result.lines,
          );
      if (result.delivered) {
        await ref.read(salesRepositoryProvider).setDelivered(saleId, true);
      }
      if (context.mounted) await showUncostedWarning(context, warnings);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _returnSale(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Devolver venta'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo de la devolución'),
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
      await ref.read(salesRepositoryProvider).confirmReturn(saleId: saleId, reason: reason);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref, Sale sale) async {
    final db = ref.read(databaseProvider);

    final customer =
        await (db.select(db.customers)..where((c) => c.id.equals(sale.customerId)))
            .getSingle();
    final user = await db.select(db.appUser).getSingleOrNull();

    final itemViews = await ref.read(saleItemsProvider(saleId).future);

    final payments = await (db.select(db.payments)
          ..where((p) => p.saleId.equals(saleId)))
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

    await shareSaleReceipt(
      storeName: user?.storeName ?? '',
      number: sale.number,
      date: sale.date,
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
      subtotal: sale.subtotal,
      discountTotal: sale.discountTotal,
      total: sale.total,
      payments: paymentLines,
      delivered: sale.delivered,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(saleByIdProvider(saleId));
    final itemsAsync = ref.watch(saleItemsProvider(saleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de venta')),
      body: saleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (sale) {
          final isDraft = sale.state == 'DRAFT';
          final isConfirmed = sale.state == 'CONFIRMED';

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Venta ${sale.number}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Chip(label: Text(isDraft ? 'Borrador' : sale.state)),
                  ],
                ),
              ),
              Expanded(
                child: itemsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                  data: (items) {
                    if (items.isEmpty) {
                      return const Center(child: Text('Sin productos aún.'));
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final it = items[i].item;
                        return ListTile(
                          title: Text(items[i].productName),
                          subtitle: Text(
                            '${it.quantity} x ${formatCopWithSymbol(it.unitPrice)}'
                            '${it.discount > 0 ? ' · Desc: ${formatCopWithSymbol(it.discount)}' : ''}',
                          ),
                          trailing: isDraft
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => ref
                                      .read(salesRepositoryProvider)
                                      .removeItem(it.id, saleId),
                                )
                              : Text(formatCopWithSymbol(it.lineTotal)),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TotalsRow(label: 'Subtotal', value: sale.subtotal),
                    _TotalsRow(label: 'Descuento', value: -sale.discountTotal),
                    _TotalsRow(label: 'Total', value: sale.total, bold: true),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Comisión (${sale.commissionRate.toStringAsFixed(1)}%): '
                          '${formatCopWithSymbol(sale.commissionAmount)}',
                        ),
                        if (isDraft)
                          TextButton(
                            onPressed: () => _editCommission(context, ref, sale),
                            child: const Text('Editar'),
                          ),
                      ],
                    ),
                    if (isConfirmed)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Entregado al cliente'),
                        value: sale.delivered,
                        onChanged: (v) =>
                            ref.read(salesRepositoryProvider).setDelivered(saleId, v),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: isDraft
                    ? Column(
                        children: [
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
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _confirmSale(context, ref, sale),
                            icon: const Icon(Icons.check),
                            label: const Text('Cobrar y confirmar'),
                          ),
                        ],
                      )
                    : (isConfirmed
                        ? Column(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _exportPdf(context, ref, sale),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Descargar / compartir PDF'),
                              ),
                              if (!sale.isReturn) ...[
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _returnSale(context, ref),
                                  icon: const Icon(Icons.undo),
                                  label: const Text('Devolver venta'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          )
                        : const SizedBox.shrink()),
              ),
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
