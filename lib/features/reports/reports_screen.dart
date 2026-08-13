import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/currency_input_formatter.dart';
import '../../core/pdf/reports_pdf.dart';
import '../../core/providers.dart';
import 'reports_providers.dart';

const _weekdayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _monthLabels = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

const _periodTitles = {
  ReportPeriod.week: 'Ventas últimos 7 días',
  ReportPeriod.month: 'Ventas este mes',
  ReportPeriod.year: 'Ventas este año',
};

const _periodExportLabels = {
  ReportPeriod.week: 'Últimos 7 días',
  ReportPeriod.month: 'Este mes',
  ReportPeriod.year: 'Este año',
};

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _exportPdf(BuildContext context, WidgetRef ref, ReportPeriod period) async {
    final db = ref.read(databaseProvider);
    final user = await db.select(db.appUser).getSingleOrNull();

    final profit = await ref.read(profitSummaryProvider.future);
    final days = await ref.read(salesByPeriodProvider.future);
    final products = await ref.read(topProductsProvider.future);
    final commissions = await ref.read(commissionsByEmployeeProvider.future);
    final expenses = await ref.read(expensesByCategoryProvider.future);

    final (start, end) = periodRange(period);
    final rangeEndInclusive = end.subtract(const Duration(days: 1));

    final salesRows = [
      for (final d in days)
        (
          switch (period) {
            ReportPeriod.week =>
              '${_weekdayLabels[d.day.weekday - 1]} ${d.day.day}/${d.day.month}',
            ReportPeriod.month => '${d.day.day}/${d.day.month}',
            ReportPeriod.year => _monthLabels[d.day.month - 1],
          },
          d.total,
        ),
    ];

    if (!context.mounted) return;
    await shareAnalysisReportPdf(
      storeName: user?.storeName ?? '',
      periodLabel: _periodExportLabels[period]!,
      rangeStart: start,
      rangeEnd: rangeEndInclusive,
      netSales: profit.netSales,
      cost: profit.cost,
      utility: profit.utility,
      marginPct: profit.marginPct,
      salesByBucket: salesRows,
      products: [
        for (final p in products)
          ReportProductRow(
            name: p.productName,
            quantity: p.quantity,
            revenue: p.revenue,
            cost: p.cost,
            utility: p.utility,
            marginPct: p.marginPct,
          ),
      ],
      commissions: [for (final c in commissions) (c.employeeName, c.amount)],
      expenses: [for (final e in expenses) (e.categoryName, e.amount)],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final salesAsync = ref.watch(salesByPeriodProvider);
    final profitAsync = ref.watch(profitSummaryProvider);
    final topProductsAsync = ref.watch(topProductsProvider);
    final commissionsAsync = ref.watch(commissionsByEmployeeProvider);
    final expensesAsync = ref.watch(expensesByCategoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Análisis del negocio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Resumen', style: Theme.of(context).textTheme.titleMedium),
              SegmentedButton<ReportPeriod>(
                segments: const [
                  ButtonSegment(value: ReportPeriod.week, label: Text('Semana')),
                  ButtonSegment(value: ReportPeriod.month, label: Text('Mes')),
                  ButtonSegment(value: ReportPeriod.year, label: Text('Año')),
                ],
                selected: {period},
                onSelectionChanged: (selection) =>
                    ref.read(reportPeriodProvider.notifier).state = selection.first,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _exportPdf(context, ref, period),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Descargar / compartir PDF'),
            ),
          ),
          const SizedBox(height: 12),
          profitAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Text('Error: $e'),
            data: (p) {
              final wide = MediaQuery.of(context).size.width >= 700;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: wide ? 4 : 2,
                childAspectRatio: 1.7,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _ProfitCard(
                    label: 'Ventas netas',
                    value: formatCopWithSymbol(p.netSales),
                    icon: Icons.point_of_sale_outlined,
                  ),
                  _ProfitCard(
                    label: 'Costo de ventas',
                    value: formatCopWithSymbol(p.cost),
                    icon: Icons.inventory_2_outlined,
                  ),
                  _ProfitCard(
                    label: 'Utilidad bruta',
                    value: formatCopWithSymbol(p.utility),
                    icon: Icons.savings_outlined,
                    valueColor: p.utility >= 0 ? Colors.green : Colors.red,
                  ),
                  _ProfitCard(
                    label: 'Margen bruto',
                    value: '${p.marginPct.toStringAsFixed(1)}%',
                    icon: Icons.percent,
                    valueColor: p.marginPct >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text(_periodTitles[period]!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (days) {
                final maxY = days.map((d) => d.total).fold<int>(0, (a, b) => a > b ? a : b);
                final barWidth = switch (period) {
                  ReportPeriod.week => 18.0,
                  ReportPeriod.month => 6.0,
                  ReportPeriod.year => 14.0,
                };
                return BarChart(
                  BarChartData(
                    maxY: maxY == 0 ? 1 : maxY * 1.2,
                    barGroups: [
                      for (var i = 0; i < days.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: days[i].total.toDouble(),
                              color: Theme.of(context).colorScheme.primary,
                              width: barWidth,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: period == ReportPeriod.month ? 5 : 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= days.length) return const SizedBox();
                            final d = days[i].day;
                            final label = switch (period) {
                              ReportPeriod.week => _weekdayLabels[d.weekday - 1],
                              ReportPeriod.month => '${d.day}',
                              ReportPeriod.year => _monthLabels[d.month - 1],
                            };
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(label, style: const TextStyle(fontSize: 11)),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                          formatCopWithSymbol(rod.toY.round()),
                          const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          Text('Detalle por producto', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          topProductsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
            data: (products) {
              if (products.isEmpty) {
                return const Text('Aún no hay ventas confirmadas en este periodo.');
              }
              return Column(
                children: [
                  for (final p in products)
                    ListTile(
                      leading: const Icon(Icons.trending_up),
                      title: Text(p.productName),
                      subtitle: Text(
                        '${p.quantity} unidades · Costo ${formatCopWithSymbol(p.cost)}',
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCopWithSymbol(p.revenue),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Margen ${p.marginPct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.marginPct >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Text('Comisiones por vendedor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          commissionsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
            data: (commissions) {
              if (commissions.isEmpty) {
                return const Text('Aún no hay comisiones generadas en este periodo.');
              }
              return Column(
                children: [
                  for (final c in commissions)
                    ListTile(
                      leading: const Icon(Icons.percent),
                      title: Text(c.employeeName),
                      trailing: Text(formatCopWithSymbol(c.amount)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Text('Gastos por categoría', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          expensesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
            data: (expenses) {
              if (expenses.isEmpty) {
                return const Text('Aún no hay gastos registrados en este periodo.');
              }
              return Column(
                children: [
                  for (final e in expenses)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(e.categoryName),
                      trailing: Text(formatCopWithSymbol(e.amount)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: scheme.primary),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
