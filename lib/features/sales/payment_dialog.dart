import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../people/people_providers.dart';
import 'sales_providers.dart';

/// Diálogo de pago reutilizable para Ventas y abonos de Apartados: soporta
/// pago mixto (parte efectivo, parte consignación a una cuenta), tal como
/// pidió el cliente.
class _DraftLine {
  _DraftLine({required this.method, required this.amount});
  String method;
  int amount;
  int? accountId;
}

Future<List<PaymentLineInput>?> showPaymentDialog(
  BuildContext context, {
  required int totalToPay,
  required String title,
  bool allowPartial = false,
}) {
  return showDialog<List<PaymentLineInput>>(
    context: context,
    builder: (context) => _PaymentDialog(
      totalToPay: totalToPay,
      title: title,
      allowPartial: allowPartial,
    ),
  );
}

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({
    required this.totalToPay,
    required this.title,
    required this.allowPartial,
  });
  final int totalToPay;
  final String title;
  final bool allowPartial;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final List<_DraftLine> _lines = [];

  int get _paid => _lines.fold(0, (sum, l) => sum + l.amount);
  int get _remaining => widget.totalToPay - _paid;

  bool get _canConfirm {
    if (_lines.isEmpty || _remaining < 0) return false;
    return widget.allowPartial ? _paid > 0 : _remaining == 0;
  }

  void _addLine(String method) {
    setState(() {
      _lines.add(_DraftLine(method: method, amount: _remaining > 0 ? _remaining : 0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(paymentAccountsStreamProvider);
    final accounts = accountsAsync.value ?? const <PaymentAccount>[];

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.allowPartial ? 'Saldo pendiente' : 'Total a pagar'}: '
              '${formatCopWithSymbol(widget.totalToPay)}',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _lines.length; i++) ...[
              _PaymentLineEditor(
                line: _lines[i],
                accounts: accounts,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _lines.removeAt(i)),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addLine('CASH'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Efectivo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addLine('CONSIGNMENT'),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Consignación'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _remaining == 0
                  ? 'Pago completo'
                  : (widget.allowPartial && _remaining > 0 && _remaining < widget.totalToPay
                      ? 'Queda pendiente después de este abono: '
                          '${formatCopWithSymbol(_remaining)}'
                      : 'Restante: ${formatCopWithSymbol(_remaining)}'),
              style: TextStyle(
                color: _remaining == 0
                    ? Colors.green
                    : (widget.allowPartial ? Colors.blueGrey : Colors.orange),
                fontWeight: FontWeight.bold,
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
          onPressed: _canConfirm
              ? () {
                  Navigator.pop(
                    context,
                    _lines
                        .map((l) => PaymentLineInput(
                              method: l.method,
                              amount: l.amount,
                              accountId: l.accountId,
                            ))
                        .toList(),
                  );
                }
              : null,
          child: const Text('Confirmar pago'),
        ),
      ],
    );
  }
}

const _newAccountSentinel = -1;

class _PaymentLineEditor extends ConsumerStatefulWidget {
  const _PaymentLineEditor({
    required this.line,
    required this.accounts,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftLine line;
  final List<PaymentAccount> accounts;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  ConsumerState<_PaymentLineEditor> createState() => _PaymentLineEditorState();
}

class _PaymentLineEditorState extends ConsumerState<_PaymentLineEditor> {
  late final TextEditingController _amountCtrl =
      TextEditingController(text: formatCop(widget.line.amount));

  Future<void> _createAccountInline() async {
    final labelCtrl = TextEditingController();
    final bankCtrl = TextEditingController();

    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva cuenta de consignación'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'A quién se le consigna (tú, un empleado, etc.)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankCtrl,
                decoration: const InputDecoration(labelText: 'Banco (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, labelCtrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;

    final id = await ref
        .read(peopleRepositoryProvider)
        .savePaymentAccount(label: label, bankName: bankCtrl.text.trim());
    widget.line.accountId = id;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isConsignment = widget.line.method == 'CONSIGNMENT';
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(isConsignment ? Icons.account_balance_outlined : Icons.payments_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(isConsignment ? 'Consignación' : 'Efectivo')),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
              onChanged: (v) {
                widget.line.amount = ThousandsInputFormatter.parse(v);
                widget.onChanged();
              },
            ),
            if (isConsignment) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey(widget.line.accountId),
                initialValue: widget.line.accountId,
                decoration: const InputDecoration(labelText: 'Cuenta destino'),
                items: [
                  for (final a in widget.accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.label)),
                  const DropdownMenuItem(
                    value: _newAccountSentinel,
                    child: Text('+ Nueva cuenta...'),
                  ),
                ],
                onChanged: (v) {
                  if (v == _newAccountSentinel) {
                    _createAccountInline();
                    return;
                  }
                  widget.line.accountId = v;
                  widget.onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
