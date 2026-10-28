import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../reports/reports_providers.dart' show ReportPeriod;

/// Periodo de Auditoría, independiente del que se usa en Análisis (cada
/// módulo se filtra por su cuenta). Nulo = todo el historial.
final auditPeriodProvider = StateProvider.autoDispose<ReportPeriod?>((ref) => null);

/// Categorías de Auditoría. Solo las que son salidas reales de plata suman
/// al total; la compra es un compromiso (su pago aparece aparte).
class AuditCategory {
  AuditCategory._();
  static const expense = 'Gasto';
  static const commission = 'Comisión';
  static const supplierPayment = 'Pago a proveedor';
  static const purchase = 'Compra (compromiso)';

  static const all = [expense, supplierPayment, commission, purchase];
}

class AuditEntry {
  const AuditEntry({
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
    required this.isOutflow,
  });
  final DateTime date;
  final String category;
  final String description;

  /// Cuánto salió (o, en una compra, cuánto se comprometió a pagar).
  /// Negativo si es un reverso (ej. un pago a proveedor devuelto).
  final int amount;

  /// true = plata que de verdad salió del negocio (suma al total).
  /// false = compromiso (compra): se muestra pero no se suma, porque su
  /// pago ya aparece como "Pago a proveedor" (al contado o cuando se abone).
  final bool isOutflow;
}

/// Historial de lo que sale o se compromete del negocio: gastos, pagos de
/// comisión y pagos a proveedores (salidas reales, tomadas del libro de
/// caja) y compras de mercancía (compromiso, se hayan pagado o no).
final auditEntriesProvider = StreamProvider.autoDispose<List<AuditEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.cashMovements).watch().map((_) {}),
    db.select(db.purchases).watch().map((_) {}),
  ]);

  return trigger.asyncMap((_) async {
    final entries = <AuditEntry>[];

    final employees = await db.select(db.employees).get();
    final employeeNameById = {for (final e in employees) e.id: e.name};
    final suppliers = await db.select(db.suppliers).get();
    final supplierNameById = {for (final s in suppliers) s.id: s.name};

    // Salidas reales, del libro de caja único. Los pagos "directo a
    // proveedor" que hace un cliente (método SUPPLIER) no salen de la caja
    // ni del banco del negocio, así que no son una salida aquí.
    final cashRows = await (db.select(db.cashMovements)
          ..where((c) =>
              c.type.isIn(['EXPENSE', 'COMMISSION_PAYMENT', 'SUPPLIER_PAYMENT']) &
              c.method.equals('SUPPLIER').not()))
        .get();
    for (final r in cashRows) {
      final (category, description) = switch (r.type) {
        'EXPENSE' => (AuditCategory.expense, r.detail.isEmpty ? 'Gasto' : r.detail),
        'COMMISSION_PAYMENT' => (AuditCategory.commission, employeeNameById[r.refId] ?? 'Vendedor'),
        _ => (
            AuditCategory.supplierPayment,
            '${r.detail.isEmpty ? 'Pago' : r.detail} · ${supplierNameById[r.refId] ?? 'Proveedor'}',
          ),
      };
      entries.add(AuditEntry(
        date: r.date,
        category: category,
        description: description,
        amount: -r.amount,
        isOutflow: true,
      ));
    }

    // Compras de mercancía: TODAS las confirmadas, pagadas de una o a
    // crédito — comprar es el evento que importa auditar. Pero NO suman al
    // total: lo que de verdad salió es su pago (arriba).
    final purchaseQuery = db.select(db.purchases).join([
      innerJoin(db.suppliers, db.suppliers.id.equalsExp(db.purchases.supplierId)),
    ])
      ..where(db.purchases.state.equals('CONFIRMED'));
    for (final row in await purchaseQuery.get()) {
      final purchase = row.readTable(db.purchases);
      final supplier = row.readTable(db.suppliers);
      entries.add(AuditEntry(
        date: purchase.date,
        category: AuditCategory.purchase,
        description: 'Compra ${purchase.number} · ${supplier.name}'
            '${purchase.paymentType == 'CREDIT' ? ' (a crédito)' : ' (de contado)'}',
        amount: purchase.total,
        isOutflow: false,
      ));
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  });
});

/// Totales de una lista de Auditoría: lo que salió de verdad y lo
/// comprometido en compras (que no se suma).
({int outflow, int committed}) auditTotals(List<AuditEntry> entries) => (
      outflow: entries.where((e) => e.isOutflow).fold(0, (a, e) => a + e.amount),
      committed: entries.where((e) => !e.isOutflow).fold(0, (a, e) => a + e.amount),
    );
