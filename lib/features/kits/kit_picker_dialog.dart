import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import 'kits_providers.dart';

class KitPickResult {
  const KitPickResult({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
  });
  final int productId;
  final int quantity;
  final int unitPrice;
  final int discount;
}

/// Deja elegir un kit y marcar/desmarcar sus componentes (ej. dejar el
/// vidrio afuera porque se cobra aparte) antes de agregarlos al carrito.
Future<({int kitId, List<KitPickResult> items})?> showKitPickerDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final kits = await ref.read(kitsStreamProvider.future);
  final activeKits = kits.where((k) => k.isActive).toList();
  if (!context.mounted) return null;

  if (activeKits.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay kits activos. Créalos en el módulo Kits.')),
    );
    return null;
  }

  final kit = await showDialog<Kit>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Selecciona el kit'),
      children: [
        for (final k in activeKits)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, k),
            child: Text(k.name),
          ),
      ],
    ),
  );
  if (kit == null || !context.mounted) return null;

  final components = await ref.read(kitComponentsProvider(kit.id).future);
  if (!context.mounted || components.isEmpty) return null;

  final selected = {
    for (final c in components) c.component.id: c.component.includedByDefault,
  };
  final quantities = {
    for (final c in components) c.component.id: c.component.defaultQuantity,
  };
  final priceCtrls = {
    for (final c in components)
      c.component.id: TextEditingController(text: formatCop(c.product.price)),
  };
  final discountCtrls = {
    for (final c in components) c.component.id: TextEditingController(text: '0'),
  };

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(kit.name),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in components)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: selected[c.component.id],
                            onChanged: (v) =>
                                setState(() => selected[c.component.id] = v ?? false),
                          ),
                          Expanded(child: Text(c.product.name)),
                          if (selected[c.component.id] == true) ...[
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: quantities[c.component.id]! > 1
                                  ? () => setState(() =>
                                      quantities[c.component.id] =
                                          quantities[c.component.id]! - 1)
                                  : null,
                            ),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${quantities[c.component.id]}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(() =>
                                  quantities[c.component.id] =
                                      quantities[c.component.id]! + 1),
                            ),
                          ],
                        ],
                      ),
                      if (selected[c.component.id] == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 48, right: 8, bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: priceCtrls[c.component.id],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [ThousandsInputFormatter()],
                                  decoration: const InputDecoration(
                                    labelText: 'Precio',
                                    prefixText: '\$ ',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: discountCtrls[c.component.id],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [ThousandsInputFormatter()],
                                  decoration: const InputDecoration(
                                    labelText: 'Descuento',
                                    prefixText: '\$ ',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agregar al carrito'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return null;

  final items = [
    for (final c in components)
      if (selected[c.component.id] == true)
        KitPickResult(
          productId: c.product.id,
          quantity: quantities[c.component.id]!,
          unitPrice: ThousandsInputFormatter.parse(priceCtrls[c.component.id]!.text),
          discount: ThousandsInputFormatter.parse(discountCtrls[c.component.id]!.text),
        ),
  ];

  if (items.isEmpty) return null;
  return (kitId: kit.id, items: items);
}
