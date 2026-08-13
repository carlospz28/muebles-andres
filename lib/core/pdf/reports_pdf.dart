import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../format/currency_input_formatter.dart';

class ReportProductRow {
  const ReportProductRow({
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.cost,
    required this.utility,
    required this.marginPct,
  });
  final String name;
  final int quantity;
  final int revenue;
  final int cost;
  final int utility;
  final double marginPct;
}

Future<void> shareAnalysisReportPdf({
  required String storeName,
  required String periodLabel,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required int netSales,
  required int cost,
  required int utility,
  required double marginPct,
  required List<(String label, int total)> salesByBucket,
  required List<ReportProductRow> products,
  required List<(String name, int amount)> commissions,
  required List<(String name, int amount)> expenses,
}) async {
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(
          storeName.isEmpty ? 'Muebles Andrés' : storeName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('Análisis del negocio', style: const pw.TextStyle(fontSize: 14)),
        pw.Text('Periodo: $periodLabel (${_fmtDate(rangeStart)} - ${_fmtDate(rangeEnd)})'),
        pw.Text(
          'Generado: ${_fmtDate(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 16),
        pw.Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _kpiBox('Ventas netas', formatCopWithSymbol(netSales)),
            _kpiBox('Costo de ventas', formatCopWithSymbol(cost)),
            _kpiBox('Utilidad bruta', formatCopWithSymbol(utility)),
            _kpiBox('Margen bruto', '${marginPct.toStringAsFixed(1)}%'),
          ],
        ),
        pw.SizedBox(height: 20),
        if (salesByBucket.isNotEmpty) ...[
          _sectionTitle('Ventas por periodo'),
          _simpleTable(
            ['Fecha', 'Ventas'],
            [
              for (final row in salesByBucket) [row.$1, formatCopWithSymbol(row.$2)],
            ],
          ),
          pw.SizedBox(height: 16),
        ],
        if (products.isNotEmpty) ...[
          _sectionTitle('Detalle por producto'),
          _simpleTable(
            ['Producto', 'Cant.', 'Ventas', 'Costo', 'Utilidad', 'Margen'],
            [
              for (final p in products)
                [
                  p.name,
                  '${p.quantity}',
                  formatCop(p.revenue),
                  formatCop(p.cost),
                  formatCop(p.utility),
                  '${p.marginPct.toStringAsFixed(0)}%',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
        ],
        if (commissions.isNotEmpty) ...[
          _sectionTitle('Comisiones por vendedor'),
          _simpleTable(
            ['Vendedor', 'Comisión'],
            [
              for (final c in commissions) [c.$1, formatCopWithSymbol(c.$2)],
            ],
          ),
          pw.SizedBox(height: 16),
        ],
        if (expenses.isNotEmpty) ...[
          _sectionTitle('Gastos por categoría'),
          _simpleTable(
            ['Categoría', 'Monto'],
            [
              for (final e in expenses) [e.$1, formatCopWithSymbol(e.$2)],
            ],
          ),
        ],
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}

pw.Widget _kpiBox(String label, String value) {
  return pw.Container(
    width: 120,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _simpleTable(List<String> headers, List<List<String>> rows) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [for (final h in headers) _cell(h, bold: true)],
      ),
      for (final row in rows) pw.TableRow(children: [for (final v in row) _cell(v)]),
    ],
  );
}

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
