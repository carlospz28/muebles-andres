import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../reports/reports_providers.dart' show ReportPeriod;

/// Periodo de Auditoría, independiente del que se usa en Análisis (cada
/// módulo se filtra por su cuenta). Nulo = todo el historial.
final auditPeriodProvider = StateProvider.autoDispose<ReportPeriod?>((ref) => null);

/// 'Gasto' | 'Compra de mercancía' | 'Comisión'
class AuditEntry {
  const AuditEntry({
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
  });
  final DateTime date;
  final String category;
  final String description;

  /// Siempre positivo: cuánto salió (o se comprometió a pagar) en este
  /// movimiento.
  final int amount;
}

/// Historial de salidas de dinero por gastos, compras a proveedores
/// (pagadas de una o a crédito) y pagos de comisión — todo lo que sale o
/// se compromete del negocio, en un solo lugar para poder auditar rápido.
final auditEntriesProvider = StreamProvider.autoDispose<List<AuditEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.cashMovements).watch().map((_) {}),
    db.select(db.purchases).watch().map((_) {}),
    db.select(db.supplierPayments).watch().map((_) {}),
  ]);

  return trigger.asyncMap((_) async {
    final entries = <AuditEntry>[];

    final employees = await db.select(db.employees).get();
    final employeeNameById = {for (final e in employees) e.id: e.name};

    // Gastos y comisiones: se toman del libro de caja único porque ahí
    // siempre queda registrada la salida real de dinero.
    final cashRows = await (db.select(db.cashMovements)
          ..where((c) => c.type.isIn(['EXPENSE', 'COMMISSION_PAYMENT'])))
        .get();
    for (final r in cashRows) {
      entries.add(AuditEntry(
        date: r.date,
        category: r.type == 'EXPENSE' ? 'Gasto' : 'Comisión',
        description: r.type == 'EXPENSE'
            ? (r.detail.isEmpty ? 'Gasto' : r.detail)
            : (employeeNameById[r.refId] ?? 'Vendedor'),
        amount: -r.amount,
      ));
    }

    // Compras de mercancía: TODAS las compras confirmadas, se hayan
    // pagado de una o queden a crédito — comprar mercancía es el evento
    // que importa auditar, no solo el momento en que se paga (antes solo
    // se veían las que se pagaban de contado, dejando las de crédito
    // "invisibles" en la auditoría).
    final purchaseQuery = db.select(db.purchases).join([
      innerJoin(db.suppliers, db.suppliers.id.equalsExp(db.purchases.supplierId)),
    ])
      ..where(db.purchases.state.equals('CONFIRMED'));
    final purchaseRows = await purchaseQuery.get();
    for (final row in purchaseRows) {
      final purchase = row.readTable(db.purchases);
      final supplier = row.readTable(db.suppliers);
      entries.add(AuditEntry(
        date: purchase.date,
        category: 'Compra de mercancía',
        description: 'Compra ${purchase.number} · ${supplier.name}'
            '${purchase.paymentType == 'CREDIT' ? ' (a crédito)' : ''}',
        amount: purchase.total,
      ));
    }

    // Abonos a proveedores que no vienen de una compra puntual (ej. "le
    // pagué a cuenta de lo que le debo en general").
    final standaloneQuery = db.select(db.supplierPayments).join([
      innerJoin(db.suppliers, db.suppliers.id.equalsExp(db.supplierPayments.supplierId)),
    ])
      ..where(db.supplierPayments.purchaseId.isNull());
    final standaloneRows = await standaloneQuery.get();
    for (final row in standaloneRows) {
      final payment = row.readTable(db.supplierPayments);
      final supplier = row.readTable(db.suppliers);
      entries.add(AuditEntry(
        date: payment.date,
        category: 'Compra de mercancía',
        description: 'Abono a proveedor · ${supplier.name}',
        amount: payment.amount,
      ));
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  });
});
