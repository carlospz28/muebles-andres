import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/format/currency_input_formatter.dart';
import '../../core/widgets/month_navigator.dart';
import '../expenses/expenses_screen.dart';
import 'finance_providers.dart';

/// Menú "Finanzas": las 4 entradas del módulo de Muebles Gestor, en el
/// mismo orden y con los mismos nombres y emojis.
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finanzas'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '💵 Flujo de caja'),
              Tab(text: '📈 Estado de resultados'),
              Tab(text: '⚖️ Balance'),
              Tab(text: '🏗️ Activos fijos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_CashFlowTab(), _IncomeStatementTab(), _BalanceTab(), _FixedAssetsTab()],
        ),
      ),
    );
  }
}

// ============================================================ Utilidades

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _money(int v) => formatCopWithSymbol(v);

String _pct(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} %';

Future<DateTime?> _pickDate(BuildContext context, DateTime initial, String help) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: help,
  );
}

/// Encabezado de página: título, subtítulo y acciones a la derecha.
class _PageHead extends StatelessWidget {
  const _PageHead({required this.title, required this.subtitle, this.actions = const []});
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: 10,
        spacing: 12,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
            ],
          ),
          Wrap(spacing: 10, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// Tarjeta métrica con barra de color arriba (metric-blue/green/orange/red).
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.hint, this.colors, this.valueColor});
  final String label;
  final String value;
  final String? hint;
  final List<Color>? colors;
  final Color? valueColor;

  static const blue = [Color(0xFF0D6EFD), Color(0xFF6610F2)];
  static const green = [Color(0xFF198754), Color(0xFF20C997)];
  static const orange = [Color(0xFFFD7E14), Color(0xFFFFC107)];
  static const red = [Color(0xFFDC3545), Color(0xFFFD7E14)];

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return SizedBox(
      width: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors ?? [const Color(0x8C0D6EFD), const Color(0x8C198754)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .5, color: muted),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: valueColor),
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 4),
                    Text(hint!, style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(spacing: 12, runSpacing: 12, children: children),
      );
}

/// Tabla con encabezado gris y números a la derecha.
class _Table extends StatelessWidget {
  const _Table({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;

  /// Desde esta columna en adelante (números) se alinean a la derecha.
  static const numericFrom = 1;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: .5,
      color: Theme.of(context).colorScheme.outline,
    );
    Widget cell(String t, int i, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(t, textAlign: i >= numericFrom ? TextAlign.end : TextAlign.start, style: style),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 700),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            columnWidths: const {0: FlexColumnWidth()},
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .04)),
                children: [for (var i = 0; i < headers.length; i++) cell(headers[i].toUpperCase(), i, style: head)],
              ),
              for (final r in rows)
                TableRow(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.black.withValues(alpha: .06)))),
                  children: [for (var i = 0; i < r.length; i++) cell(r[i], i)],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _asyncBody<T>(AsyncValue<T> v, Widget Function(T) builder) => v.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: builder,
    );

// ============================================================ Flujo de caja

class _CashFlowTab extends ConsumerWidget {
  const _CashFlowTab();

  Future<void> _saveOpening(BuildContext context, WidgetRef ref, CashFlowData d) async {
    final ctrl = TextEditingController(text: formatCop(d.savedOpening ?? d.openingCash));
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Caja inicial del ${_fmtDate(d.date)}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Efectivo con el que arrancó la caja este día (por ejemplo, después de contarla). '
                'Desde este día la app le suma y resta cada movimiento en efectivo, igual que '
                '"Ajustar caja" de Inicio.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(labelText: 'Base de caja', prefixText: '\$ '),
              ),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(financeRepositoryProvider)
        .saveOpeningCash(d.date, ThousandsInputFormatter.parse(ctrl.text), notesCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(cashFlowDateProvider);
    return _asyncBody(ref.watch(cashFlowProvider), (d) {
      final byMethod = d.netByMethod;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PageHead(
            title: 'Flujo de caja',
            subtitle: 'Entradas y salidas del ${_fmtDate(d.date)}',
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_fmtDate(date)),
                onPressed: () async {
                  final p = await _pickDate(context, date, 'Día');
                  if (p != null) ref.read(cashFlowDateProvider.notifier).state = dayStart(p);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Guardar caja inicial'),
                onPressed: () => _saveOpening(context, ref, d),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Registrar salida (gasto)'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpensesScreen())),
              ),
            ],
          ),
          _Metrics([
            _Metric(
              label: 'Caja inicial',
              value: _money(d.openingCash),
              hint: d.savedOpening != null ? 'Base guardada para este día' : 'Viene del día anterior (efectivo)',
              colors: _Metric.blue,
            ),
            _Metric(
              label: 'Ingresos',
              value: _money(d.totalIn),
              hint: 'Ventas ${_money(d.ingresosVentas)} · Abonos ${_money(d.ingresosAbonos)}'
                  '${d.otrosIngresos != 0 ? ' · Otros ${_money(d.otrosIngresos)}' : ''}',
              colors: _Metric.green,
            ),
            _Metric(
              label: 'Salidas',
              value: _money(d.totalOut),
              hint: 'Caja ${_money(d.egresosCaja)} · Proveedores ${_money(d.egresosProveedores)}',
              colors: _Metric.red,
            ),
            _Metric(
              label: 'Caja disponible',
              value: _money(d.closingCash),
              hint: 'Efectivo al cierre del día',
              colors: _Metric.orange,
            ),
          ]),
          if (byMethod.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in byMethod.entries)
                    Chip(label: Text('${methodLabel(e.key)}: ${_money(e.value)} neto')),
                ],
              ),
            ),
          _MovementSection('🧾 Ventas del día', d.sales),
          _MovementSection('💳 Abonos de apartados', d.layawayPayments),
          if (d.otherIncomes.isNotEmpty) _MovementSection('➕ Otros ingresos', d.otherIncomes),
          if (d.internalMoves.isNotEmpty)
            _MovementSection('🔁 Movimiento interno (retiros del banco a la caja, no es ingreso)', d.internalMoves),
          _MovementSection('🚚 Pagos a proveedores', d.supplierPayments),
          _MovementSection('💸 Salidas de caja (gastos, devoluciones, comisiones)', d.outflows),
        ],
      );
    });
  }
}

class _MovementSection extends StatelessWidget {
  const _MovementSection(this.title, this.moves);
  final String title;
  final List<CashMovement> moves;

  @override
  Widget build(BuildContext context) {
    final total = moves.fold<int>(0, (a, m) => a + m.amount);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('$title (${moves.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(_money(total.abs()), style: const TextStyle(fontWeight: FontWeight.bold)),
        children: [
          if (moves.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Sin movimientos este día.')),
          for (final m in moves)
            ListTile(
              dense: true,
              leading: Text(_fmtTime(m.date)),
              title: Text(m.detail.isEmpty ? m.type : m.detail),
              subtitle: Text(methodLabel(m.method)),
              trailing: Text(_money(m.amount.abs())),
            ),
        ],
      ),
    );
  }
}

// ===================================================== Estado de resultados

class _IncomeStatementTab extends ConsumerWidget {
  const _IncomeStatementTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _asyncBody(ref.watch(incomeStatementProvider), (s) {
      final p = s.period;
      void set(IncomePeriod v) => ref.read(incomePeriodProvider.notifier).state = v;

      final periodText = switch (p.mode) {
        IncomeMode.day => 'Día ${_fmtDate(p.start)}',
        IncomeMode.month => 'Mes de ${monthNames[p.start.month - 1]} ${p.start.year}',
        IncomeMode.range => 'Del ${_fmtDate(p.start)} al ${_fmtDate(p.end)}',
        IncomeMode.all => 'Todo (${_fmtDate(p.start)} – ${_fmtDate(p.end)})',
      };

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PageHead(title: 'Estado de resultados', subtitle: periodText, actions: [
            SegmentedButton<IncomeMode>(
              segments: const [
                ButtonSegment(value: IncomeMode.day, label: Text('Día')),
                ButtonSegment(value: IncomeMode.month, label: Text('Mes')),
                ButtonSegment(value: IncomeMode.range, label: Text('Rango')),
                ButtonSegment(value: IncomeMode.all, label: Text('Todo')),
              ],
              selected: {p.mode},
              onSelectionChanged: (sel) {
                final m = sel.first;
                switch (m) {
                  case IncomeMode.day:
                    set(IncomePeriod(m, p.end, p.end));
                  case IncomeMode.month:
                    final first = DateTime(p.end.year, p.end.month, 1);
                    set(IncomePeriod(m, first, DateTime(first.year, first.month + 1, 0)));
                  case IncomeMode.range:
                    set(IncomePeriod(m, p.start, p.end));
                  case IncomeMode.all:
                    set(IncomePeriod(m, p.start, p.end));
                }
              },
            ),
            if (p.mode == IncomeMode.day)
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_fmtDate(p.start)),
                onPressed: () async {
                  final d = await _pickDate(context, p.start, 'Día');
                  if (d != null) set(IncomePeriod(IncomeMode.day, dayStart(d), dayStart(d)));
                },
              ),
            if (p.mode == IncomeMode.month)
              MonthNavigator(
                month: p.start,
                onChanged: (m) => set(IncomePeriod(IncomeMode.month, m, DateTime(m.year, m.month + 1, 0))),
              ),
            if (p.mode == IncomeMode.range)
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text('${_fmtDate(p.start)} – ${_fmtDate(p.end)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: DateTimeRange(start: p.start, end: p.end),
                    helpText: 'Desde / hasta',
                  );
                  if (r != null) set(IncomePeriod(IncomeMode.range, dayStart(r.start), dayStart(r.end)));
                },
              ),
          ]),
          _Metrics([
            _Metric(label: 'Ventas brutas', value: _money(s.grossSales), colors: _Metric.blue),
            _Metric(label: 'Devoluciones', value: _money(s.totalReturns), colors: _Metric.red),
            _Metric(label: 'Ventas netas', value: _money(s.netSales), colors: _Metric.blue),
            _Metric(
              label: 'Costo de ventas',
              value: _money(s.costOfSales),
              hint: 'Costo real FIFO de lo vendido',
              colors: _Metric.orange,
            ),
            _Metric(
              label: 'Utilidad bruta',
              value: _money(s.grossProfit),
              colors: _Metric.green,
              valueColor: s.grossProfit < 0 ? Colors.red : null,
            ),
            _Metric(label: 'Margen bruto', value: _pct(s.grossMarginPct), colors: _Metric.green),
          ]),
          if (s.undeliveredLayawaySales > 0)
            Card(
              color: Colors.amber.withValues(alpha: .15),
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${s.undeliveredLayawaySales} venta(s) de este periodo vienen de apartados que todavía no se '
                  'han entregado. Su costo se registra al marcarlas como entregadas, así que por ahora '
                  'la utilidad de esas ventas se ve más alta de lo real.',
                ),
              ),
            ),
          if (s.salesByDay.length > 1) _SalesChart(s.salesByDay),
          const Text('Ventas por día', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _Table(
            headers: const ['Fecha', 'Ventas', 'Costo', 'Utilidad', 'Margen'],
            rows: [
              for (final d in s.salesByDay)
                [_fmtDate(d.date), _money(d.ventas), _money(d.costo), _money(d.utilidad), _pct(d.margen)],
            ],
          ),
          const Text('Detalle por producto', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _Table(
            headers: const ['Producto', 'Cant.', 'Ventas', 'Costo', 'Utilidad', 'Margen'],
            rows: [
              for (final r in s.productRows)
                [r.name, '${r.qty}', _money(r.ventas), _money(r.costo), _money(r.utilidad), _pct(r.margen)],
            ],
          ),
        ],
      );
    });
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart(this.days);
  final List<DayResult> days;

  @override
  Widget build(BuildContext context) {
    final maxY = days.fold<int>(0, (a, d) => d.ventas > a ? d.ventas : a).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(
          children: [
            const Row(
              children: [
                _Legend(Color(0xFF0D6EFD), 'Ventas'),
                SizedBox(width: 16),
                _Legend(Color(0xFFFD7E14), 'Costo'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY == 0 ? 1 : maxY * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < days.length; i++)
                      BarChartGroupData(x: i, barsSpace: 2, barRods: [
                        BarChartRodData(toY: days[i].ventas.toDouble(), color: const Color(0xFF0D6EFD), width: 8),
                        BarChartRodData(toY: days[i].costo.toDouble(), color: const Color(0xFFFD7E14), width: 8),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: days.length > 15 ? 5 : 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= days.length) return const SizedBox();
                          final d = days[i].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

// ================================================================= Balance

class _BalanceTab extends ConsumerWidget {
  const _BalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(balanceDateProvider);
    return _asyncBody(ref.watch(balanceProvider), (b) {
      Widget line(String label, int amount, {bool bold = false, String? hint}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
                      if (hint != null)
                        Text(hint, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                Text(_money(amount), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
              ],
            ),
          );

      Widget panel(String title, List<Widget> children) => Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Divider(),
                  ...children,
                ],
              ),
            ),
          );

      final activos = panel('Activos', [
        line('Efectivo (caja)', b.efectivo, hint: 'Base de caja + movimientos en efectivo'),
        line('Consignaciones (bancos)', b.consignaciones),
        line('Cuentas por cobrar', b.cuentasPorCobrar, hint: 'Saldo pendiente de apartados en proceso'),
        line('Inventario', b.inventarioValor, hint: 'A costo, lotes FIFO actuales'),
        line('Activos fijos', b.activosFijosLibros,
            hint: 'Valor en libros (costo ${_money(b.activosFijosCosto)} − depreciación)'),
        const Divider(),
        line('Total activos', b.totalActivos, bold: true),
      ]);
      final pasivos = panel('Pasivos y patrimonio', [
        line('Proveedores por pagar', b.proveedoresPendiente),
        line('Anticipos de clientes', b.anticiposClientes, hint: 'Abonos recibidos de apartados en proceso'),
        const Divider(),
        line('Total pasivos', b.totalPasivos, bold: true),
        const SizedBox(height: 12),
        line('Patrimonio', b.patrimonio, bold: true, hint: 'Activos − pasivos'),
        const SizedBox(height: 12),
        line('Comisiones generadas (informativo)', b.commissionsTotal,
            hint: 'Comisiones de ventas hasta la fecha; no se suman al balance'),
      ]);

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PageHead(title: 'Balance', subtitle: 'Situación del negocio al ${_fmtDate(b.date)}', actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_fmtDate(date)),
              onPressed: () async {
                final p = await _pickDate(context, date, 'Fecha de corte');
                if (p != null) ref.read(balanceDateProvider.notifier).state = dayStart(p);
              },
            ),
          ]),
          _Metrics([
            _Metric(label: 'Total activos', value: _money(b.totalActivos), colors: _Metric.blue),
            _Metric(label: 'Total pasivos', value: _money(b.totalPasivos), colors: _Metric.red),
            _Metric(
              label: 'Patrimonio',
              value: _money(b.patrimonio),
              colors: _Metric.green,
              valueColor: b.patrimonio < 0 ? Colors.red : null,
            ),
          ]),
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: activos),
                    const SizedBox(width: 12),
                    Expanded(child: pasivos),
                  ])
                : Column(children: [activos, const SizedBox(height: 12), pasivos]),
          ),
          const SizedBox(height: 14),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text('Apartados con saldo (${b.layawaysConSaldo.length})'),
              children: [
                for (final l in b.layawaysConSaldo)
                  ListTile(
                    dense: true,
                    title: Text('Apartado #${l.layawayId} · ${l.customer}'),
                    subtitle: Text('${_fmtDate(l.date)} · Total ${_money(l.total)} · Abonado ${_money(l.paid)}'),
                    trailing: Text(_money(l.balance), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text('Proveedores con deuda (${b.proveedores.length})'),
              children: [
                for (final s in b.proveedores)
                  ListTile(
                    dense: true,
                    title: Text(s.name),
                    trailing: Text(_money(s.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text('Activos fijos (${b.fixedAssets.length})'),
              children: [
                for (final a in b.fixedAssets)
                  ListTile(
                    dense: true,
                    title: Text(a.name),
                    subtitle: Text(fixedAssetCategories[a.category] ?? a.category),
                    trailing: Text(_money(bookValue(a)), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ============================================================ Activos fijos

class _FixedAssetsTab extends ConsumerWidget {
  const _FixedAssetsTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [FixedAsset? a]) async {
    final nameCtrl = TextEditingController(text: a?.name ?? '');
    final costCtrl = TextEditingController(text: a == null ? '' : formatCop(a.cost));
    final depCtrl = TextEditingController(text: a == null || a.accumulatedDepreciation == 0 ? '' : formatCop(a.accumulatedDepreciation));
    final notesCtrl = TextEditingController(text: a?.notes ?? '');
    var category = a?.category ?? 'FURNITURE';
    var purchaseDate = a?.purchaseDate ?? dayStart(DateTime.now());
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(a == null ? 'Nuevo activo fijo' : 'Editar activo fijo'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(labelText: 'Nombre del activo', errorText: error),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: fixedAssetCategories.containsKey(category) ? category : 'OTHER',
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: [
                      for (final e in fixedAssetCategories.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => category = v ?? category),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de compra'),
                    subtitle: Text(_fmtDate(purchaseDate)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final d = await _pickDate(context, purchaseDate, 'Fecha de compra');
                      if (d != null) setState(() => purchaseDate = d);
                    },
                  ),
                  TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Costo de adquisición', prefixText: '\$ '),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: depCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Depreciación acumulada', prefixText: '\$ '),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setState(() => error = 'El nombre es obligatorio');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(financeRepositoryProvider).saveFixedAsset(
          id: a?.id,
          name: nameCtrl.text.trim(),
          category: category,
          purchaseDate: purchaseDate,
          cost: ThousandsInputFormatter.parse(costCtrl.text),
          accumulatedDepreciation: ThousandsInputFormatter.parse(depCtrl.text),
          notes: notesCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _asyncBody(ref.watch(fixedAssetsProvider), (assets) {
      final totalCost = assets.fold<int>(0, (s, a) => s + a.cost);
      final totalDep = assets.fold<int>(0, (s, a) => s + a.accumulatedDepreciation);
      final totalBook = assets.fold<int>(0, (s, a) => s + bookValue(a));
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PageHead(
            title: 'Activos fijos',
            subtitle: 'Mobiliario, equipos y vehículos del negocio',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nuevo activo'),
                onPressed: () => _edit(context, ref),
              ),
            ],
          ),
          if (assets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Todavía no hay activos fijos registrados.'),
            )
          else
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final a in assets) ...[
                    ListTile(
                      title: Text(a.name),
                      subtitle: Text([
                        fixedAssetCategories[a.category] ?? a.category,
                        'Compra ${_fmtDate(a.purchaseDate)}',
                        'Costo ${_money(a.cost)}',
                        if (a.accumulatedDepreciation > 0) 'Depreciación ${_money(a.accumulatedDepreciation)}',
                        if (a.notes.isNotEmpty) a.notes,
                      ].join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_money(bookValue(a)), style: const TextStyle(fontWeight: FontWeight.bold)),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') return _edit(context, ref, a);
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Borrar activo'),
                                  content: Text('¿Borrar "${a.name}"? No afecta la caja.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
                                  ],
                                ),
                              );
                              if (ok == true) await ref.read(financeRepositoryProvider).deleteFixedAsset(a.id);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Editar')),
                              PopupMenuItem(value: 'delete', child: Text('Borrar')),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _edit(context, ref, a),
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Costo ${_money(totalCost)} · Depreciación ${_money(totalDep)}'),
                    trailing: Text(_money(totalBook), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}
