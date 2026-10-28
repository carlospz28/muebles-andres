import 'dart:convert';

import 'package:archive/archive.dart';

/// Generador mínimo de archivos de Excel (.xlsx). Un .xlsx es un zip con
/// unos XML adentro; esto arma solo lo necesario (hojas, textos, números,
/// fechas, negrilla, formato de pesos y ancho de columnas) para no tener
/// que depender de una librería de Excel que obligaría a cambiar las
/// versiones de pdf/printing que usan los recibos.
class XlsxWriter {
  final List<XlsxSheet> _sheets = [];

  XlsxSheet addSheet(String name) {
    final s = XlsxSheet._(name);
    _sheets.add(s);
    return s;
  }

  List<int> encode() {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = _utf8(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 0; i < _sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');

    add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');

    add('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (var i = 0; i < _sheets.length; i++) '<sheet name="${_esc(_sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');

    add('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 0; i < _sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join('\n')}
<Relationship Id="rId${_sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');

    // Estilos (índices usados en XlsxStyle):
    // 0 normal · 1 negrilla · 2 pesos · 3 pesos negrilla · 4 encabezado ·
    // 5 fecha · 6 decimal (porcentaje con 1 decimal)
    add('xl/styles.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="&quot;\$&quot; #,##0"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDCE8E2"/></patternFill></fill></fills>
<borders count="2"><border/><border><bottom style="thin"/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment wrapText="1" vertical="center"/></xf>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
</cellXfs>
</styleSheet>''');

    for (var i = 0; i < _sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheets[i]._xml());
    }
    return ZipEncoder().encode(archive);
  }
}

enum XlsxStyle { normal, bold, money, moneyBold, header, date, decimal }

/// Valor de pesos (se muestra como "$ 1.234.567").
class Money {
  const Money(this.value);
  final int value;
}

class XlsxSheet {
  XlsxSheet._(this.name);
  final String name;
  final List<List<(Object?, XlsxStyle)>> _rows = [];
  final Map<int, double> _widths = {};

  void setWidths(List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      _widths[i] = widths[i];
    }
  }

  /// Agrega una fila. Valores: String, int, double, DateTime, [Money] o null.
  void row(List<Object?> values, {bool bold = false, bool header = false}) {
    _rows.add([
      for (final v in values)
        (
          v,
          header
              ? XlsxStyle.header
              : v is Money
                  ? (bold ? XlsxStyle.moneyBold : XlsxStyle.money)
                  : v is DateTime
                      ? XlsxStyle.date
                      : v is double
                          ? XlsxStyle.decimal
                          : bold
                              ? XlsxStyle.bold
                              : XlsxStyle.normal,
        ),
    ]);
  }

  String _xml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    if (_widths.isNotEmpty) {
      b.write('<cols>');
      _widths.forEach((i, w) => b.write('<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>'));
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < _rows.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < _rows[r].length; c++) {
        final (value, style) = _rows[r][c];
        if (value == null) continue;
        final ref = '${_col(c)}${r + 1}';
        final s = style.index;
        if (value is Money) {
          b.write('<c r="$ref" s="$s"><v>${value.value}</v></c>');
        } else if (value is num) {
          b.write('<c r="$ref" s="$s"><v>$value</v></c>');
        } else if (value is DateTime) {
          b.write('<c r="$ref" s="$s"><v>${_excelDate(value)}</v></c>');
        } else {
          b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${_esc(value.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }
}

/// Número de columna (0 = A) a letras de Excel.
String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Excel cuenta los días desde el 30/12/1899.
int _excelDate(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Caracteres de control no permitidos en XML.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

List<int> _utf8(String s) => utf8.encode(s);
