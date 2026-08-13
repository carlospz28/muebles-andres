import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../format/currency_input_formatter.dart';

class ReceiptLine {
  const ReceiptLine({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
  final String productName;
  final int quantity;
  final int unitPrice;
  final int lineTotal;
}

class ReceiptPaymentLine {
  const ReceiptPaymentLine({required this.label, required this.amount});
  final String label;
  final int amount;
}

Future<void> shareSaleReceipt({
  required String storeName,
  required String number,
  required DateTime date,
  required String customerName,
  required List<ReceiptLine> items,
  required int subtotal,
  required int discountTotal,
  required int total,
  required List<ReceiptPaymentLine> payments,
  required bool delivered,
}) async {
  final doc = _buildReceipt(
    storeName: storeName,
    title: 'Venta $number',
    date: date,
    customerName: customerName,
    items: items,
    subtotal: subtotal,
    discountTotal: discountTotal,
    total: total,
    payments: payments,
    extraRows: [
      ('Entregado', delivered ? 'Sí' : 'No'),
    ],
  );
  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

Future<void> shareLayawayReceipt({
  required String storeName,
  required int layawayId,
  required DateTime date,
  required String customerName,
  required List<ReceiptLine> items,
  required int total,
  required int paid,
  required int balance,
  required List<ReceiptPaymentLine> payments,
  required bool delivered,
}) async {
  final doc = _buildReceipt(
    storeName: storeName,
    title: 'Apartado #$layawayId',
    date: date,
    customerName: customerName,
    items: items,
    subtotal: total,
    discountTotal: 0,
    total: total,
    payments: payments,
    extraRows: [
      ('Pagado', formatCopWithSymbol(paid)),
      ('Saldo pendiente', formatCopWithSymbol(balance)),
      ('Entregado', delivered ? 'Sí' : 'No'),
    ],
  );
  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

pw.Document _buildReceipt({
  required String storeName,
  required String title,
  required DateTime date,
  required String customerName,
  required List<ReceiptLine> items,
  required int subtotal,
  required int discountTotal,
  required int total,
  required List<ReceiptPaymentLine> payments,
  required List<(String, String)> extraRows,
}) {
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              storeName.isEmpty ? 'Muebles Andrés' : storeName,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(title, style: const pw.TextStyle(fontSize: 14)),
            pw.Text('Fecha: ${date.day}/${date.month}/${date.year}'),
            pw.Text('Cliente: $customerName'),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Producto', bold: true),
                    _cell('Cant.', bold: true),
                    _cell('Precio', bold: true),
                    _cell('Total', bold: true),
                  ],
                ),
                for (final it in items)
                  pw.TableRow(
                    children: [
                      _cell(it.productName),
                      _cell('${it.quantity}'),
                      _cell(formatCop(it.unitPrice)),
                      _cell(formatCop(it.lineTotal)),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 12),
            _totalsRow('Subtotal', subtotal),
            if (discountTotal > 0) _totalsRow('Descuento', -discountTotal),
            _totalsRow('Total', total, bold: true),
            pw.SizedBox(height: 8),
            if (payments.isNotEmpty) ...[
              pw.Text('Pago', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final p in payments) _totalsRow(p.label, p.amount),
              pw.SizedBox(height: 8),
            ],
            for (final row in extraRows) _totalsRow(row.$1, null, textValue: row.$2),
            pw.SizedBox(height: 16),
            pw.Text(
              'Gracias por su compra.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        );
      },
    ),
  );

  return doc;
}

pw.Widget _cell(String text, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}

pw.Widget _totalsRow(String label, int? value, {bool bold = false, String? textValue}) {
  final style = pw.TextStyle(
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(textValue ?? formatCopWithSymbol(value ?? 0), style: style),
      ],
    ),
  );
}
