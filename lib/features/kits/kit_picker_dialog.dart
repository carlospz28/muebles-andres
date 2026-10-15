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

  var search = '';
  final kit = await showDialog<Kit>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final filtered = search.isEmpty
            ? activeKits
            : activeKits
                .where((k) => k.name.toLowerCase().contains(search.toLowerCase()))
                .toList();

        return SimpleDialog(
          title: const Text('Selecciona el kit'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar kit...',
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
            const SizedBox(height: 8),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Sin resultados.'),
              ),
            for (final k in filtered)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, k),
                child: Text(k.name),
              ),
          ],
        );
      },
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
  final finalPriceCtrl = TextEditingController();
  var lastAutoFinalPrice = '';

  int suggestedTotal() {
    var total = 0;
    for (final c in components) {
      if (selected[c.component.id] != true) continue;
      final qty = quantities[c.component.id]!;
      final price = ThousandsInputFormatter.parse(priceCtrls[c.component.id]!.text);
      final discount = ThousandsInputFormatter.parse(discountCtrls[c.component.id]!.text);
      total += qty * price - discount;
    }
    return total < 0 ? 0 : total;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        // Precio sugerido = suma de los componentes seleccionados. Si el
        // usuario no ha tocado el campo de precio final, lo mantenemos
        // sincronizado; en cuanto lo edita, dejamos de tocarlo.
        final suggested = suggestedTotal();
        final suggestedText = formatCop(suggested);
        if (finalPriceCtrl.text == lastAutoFinalPrice) {
          finalPriceCtrl.text = suggestedText;
          lastAutoFinalPrice = suggestedText;
        }

        return AlertDialog(
          title: Text(kit.name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
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
                                      onChanged: (_) => setState(() {}),
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
                                      onChanged: (_) => setState(() {}),
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
                  const Divider(height: 24),
                  TextField(
                    controller: finalPriceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Precio final del kit',
                      helperText: 'Sugerido: \$$suggestedText — cámbialo si le vas a '
                          'hacer descuento al kit completo.',
                      prefixText: '\$ ',
                    ),
                  ),
                ],
              ),
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
        );
      },
    ),
  );

  if (confirmed != true) return null;

  final selectedComponents = components.where((c) => selected[c.component.id] == true).toList();
  if (selectedComponents.isEmpty) return null;

  // Línea base de cada componente con su precio/descuento tal cual se
  // editaron. Si el usuario cambió el "precio final del kit", la diferencia
  // con la suma de estas líneas se reparte proporcionalmente como
  // descuento adicional, para no perder el precio unitario real de cada
  // producto (importante para el costeo y los reportes por producto).
  final rawLines = [
    for (final c in selectedComponents)
      (
        productId: c.product.id,
        quantity: quantities[c.component.id]!,
        unitPrice: ThousandsInputFormatter.parse(priceCtrls[c.component.id]!.text),
        discount: ThousandsInputFormatter.parse(discountCtrls[c.component.id]!.text),
      ),
  ];
  final rawTotal = rawLines.fold<int>(
    0,
    (sum, l) => sum + (l.quantity * l.unitPrice - l.discount),
  );
  final finalPrice = ThousandsInputFormatter.parse(finalPriceCtrl.text);
  final extraDiscount = rawTotal - finalPrice;

  final items = <KitPickResult>[];
  var distributed = 0;
  for (var i = 0; i < rawLines.length; i++) {
    final l = rawLines[i];
    final lineRaw = l.quantity * l.unitPrice - l.discount;
    int extraForLine;
    if (i == rawLines.length - 1) {
      extraForLine = extraDiscount - distributed;
    } else if (rawTotal > 0) {
      extraForLine = (extraDiscount * lineRaw / rawTotal).round();
    } else {
      extraForLine = 0;
    }
    distributed += extraForLine;

    items.add(KitPickResult(
      productId: l.productId,
      quantity: l.quantity,
      unitPrice: l.unitPrice,
      discount: l.discount + extraForLine,
    ));
  }

  return (kitId: kit.id, items: items);
}
