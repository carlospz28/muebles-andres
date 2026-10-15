import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../inventory/catalog_providers.dart';
import '../sales/payment_dialog.dart';
import '../sales/sales_providers.dart' show PaymentLineInput;
import 'purchases_providers.dart';

class PurchaseFormScreen extends ConsumerWidget {
  const PurchaseFormScreen({super.key, required this.purchaseId});

  final int purchaseId;

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final products = await ref.read(productsStreamProvider.future);
    if (!context.mounted) return;

    Product? selected;
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController();
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
                          subtitle: Text('SKU ${p.sku}'),
                          onTap: () => setState(() => selected = p),
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
                      controller: costCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Costo unitario de este lote',
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
                    final cost = ThousandsInputFormatter.parse(costCtrl.text);
                    if (qty <= 0 || cost <= 0) return;
                    await ref.read(purchasesRepositoryProvider).addItem(
                          purchaseId: purchaseId,
                          productId: selected!.id,
                          quantity: qty,
                          unitCost: cost,
                        );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Agregar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final items = await ref.read(purchaseItemsProvider(purchaseId).future);
    if (!context.mounted || items.isEmpty) return;
    final total = items.fold<int>(0, (sum, v) => sum + v.item.lineTotal);

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar compra'),
        content: Text(
          'Esto suma el stock de cada producto. Total: ${formatCopWithSymbol(total)}.\n'
          '¿Cómo se paga?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'CREDIT'),
            child: const Text('A crédito'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'CASH'),
            child: const Text('Pagar ahora'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    var lines = const <PaymentLineInput>[];
    if (choice == 'CASH') {
      final result = await showPaymentDialog(
        context,
        totalToPay: total,
        title: 'Pago al proveedor',
      );
      if (result == null) return;
      lines = result.lines;
    }
    if (!context.mounted) return;

    try {
      await ref
          .read(purchasesRepositoryProvider)
          .confirmPurchase(purchaseId, paymentLines: lines);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchaseAsync = ref.watch(purchaseByIdProvider(purchaseId));
    final itemsAsync = ref.watch(purchaseItemsProvider(purchaseId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de compra')),
      body: purchaseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (purchase) {
          final isDraft = purchase.state == 'DRAFT';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Compra ${purchase.number}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Chip(label: Text(isDraft ? 'Borrador' : purchase.state)),
                  ],
                ),
              ),
              if (!isDraft)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      purchase.paymentType == 'CREDIT'
                          ? 'A crédito — ver saldo con el proveedor en Proveedores.'
                          : 'Pagada de contado al confirmar.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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
                            '${it.quantity} x ${formatCopWithSymbol(it.unitCost)}',
                          ),
                          trailing: isDraft
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => ref
                                      .read(purchasesRepositoryProvider)
                                      .removeItem(it.id),
                                )
                              : Text(formatCopWithSymbol(it.lineTotal)),
                        );
                      },
                    );
                  },
                ),
              ),
              if (isDraft)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _addItem(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar producto'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _confirm(context, ref),
                          icon: const Icon(Icons.check),
                          label: const Text('Confirmar compra'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
