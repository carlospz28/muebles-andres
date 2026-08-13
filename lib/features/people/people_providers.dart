import 'package:async/async.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';

final customersStreamProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

final employeesStreamProvider = StreamProvider.autoDispose<List<Employee>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.employees)..orderBy([(e) => OrderingTerm.asc(e.name)]))
      .watch();
});

/// Solo los vendedores activos — para elegir a quién asignarle una venta o
/// apartado NUEVO. Un vendedor desactivado no debe poder seguir generando
/// comisiones nuevas, pero sigue apareciendo en el reporte de comisiones
/// (con lo que ya se le debe) y en su propio historial de ventas pasadas.
final activeEmployeesStreamProvider = StreamProvider.autoDispose<List<Employee>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.employees)
        ..where((e) => e.isActive.equals(true))
        ..orderBy([(e) => OrderingTerm.asc(e.name)]))
      .watch();
});

final suppliersStreamProvider = StreamProvider.autoDispose<List<Supplier>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.suppliers)..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();
});

final paymentAccountsStreamProvider =
    StreamProvider.autoDispose<List<PaymentAccount>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.paymentAccounts)
        ..orderBy([(a) => OrderingTerm.asc(a.label)]))
      .watch();
});

class AccountBalance {
  const AccountBalance(this.account, this.balance);
  final PaymentAccount account;
  final int balance;
}

/// Saldo por cuenta de consignación: lo que han pagado clientes/apartados
/// por transferencia a esa cuenta, menos lo que se les ha pagado a
/// proveedores desde/hacia esa misma cuenta.
final accountBalancesProvider = StreamProvider.autoDispose<List<AccountBalance>>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.paymentAccounts).watch().map((_) {}),
    db.select(db.paymentLines).watch().map((_) {}),
    db.select(db.supplierPayments).watch().map((_) {}),
  ]);

  return trigger.asyncMap((_) async {
    final accounts = await db.select(db.paymentAccounts).get();
    final balances = <int, int>{for (final a in accounts) a.id: 0};

    final lines = await (db.select(db.paymentLines)
          ..where((l) => l.method.equals('CONSIGNMENT')))
        .get();
    for (final l in lines) {
      final accountId = l.accountId;
      if (accountId == null) continue;
      balances[accountId] = (balances[accountId] ?? 0) + l.amount;
    }

    final supplierPayments = await (db.select(db.supplierPayments)
          ..where((p) => p.method.equals('CONSIGNMENT')))
        .get();
    for (final p in supplierPayments) {
      final accountId = p.accountId;
      if (accountId == null) continue;
      balances[accountId] = (balances[accountId] ?? 0) - p.amount;
    }

    return [for (final a in accounts) AccountBalance(a, balances[a.id] ?? 0)];
  });
});

class AccountMovement {
  const AccountMovement({
    required this.date,
    required this.amount,
    required this.description,
  });
  final DateTime date;
  final int amount;
  final String description;
}

/// Historial de movimientos de una cuenta de consignación: de dónde vino
/// cada pago (venta, abono de apartado, o pago a proveedor) y cuándo —
/// para que cuadrar cuentas no sea adivinar de dónde salió cada plata.
final accountMovementsProvider =
    StreamProvider.autoDispose.family<List<AccountMovement>, int>((ref, accountId) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.paymentLines).watch().map((_) {}),
    db.select(db.supplierPayments).watch().map((_) {}),
  ]);

  Future<List<AccountMovement>> load() async {
    final movements = <AccountMovement>[];

    final lineQuery = db.select(db.paymentLines).join([
      innerJoin(db.payments, db.payments.id.equalsExp(db.paymentLines.paymentId)),
    ])
      ..where(db.paymentLines.accountId.equals(accountId) &
          db.paymentLines.method.equals('CONSIGNMENT'));
    final lineRows = await lineQuery.get();

    for (final row in lineRows) {
      final line = row.readTable(db.paymentLines);
      final payment = row.readTable(db.payments);
      String description;
      if (payment.saleId != null) {
        final sale = await (db.select(db.sales)..where((s) => s.id.equals(payment.saleId!)))
            .getSingleOrNull();
        final customer = sale == null
            ? null
            : await (db.select(db.customers)..where((c) => c.id.equals(sale.customerId)))
                .getSingleOrNull();
        description = 'Venta ${sale?.number ?? '?'}'
            '${customer != null ? ' · ${customer.name}' : ''}';
      } else if (payment.layawayId != null) {
        final layaway = await (db.select(db.layaways)
              ..where((l) => l.id.equals(payment.layawayId!)))
            .getSingleOrNull();
        final customer = layaway == null
            ? null
            : await (db.select(db.customers)..where((c) => c.id.equals(layaway.customerId)))
                .getSingleOrNull();
        description = 'Abono apartado #${payment.layawayId}'
            '${customer != null ? ' · ${customer.name}' : ''}';
      } else {
        description = 'Pago';
      }
      movements.add(
        AccountMovement(date: payment.date, amount: line.amount, description: description),
      );
    }

    final supplierQuery = db.select(db.supplierPayments).join([
      innerJoin(db.suppliers, db.suppliers.id.equalsExp(db.supplierPayments.supplierId)),
    ])
      ..where(db.supplierPayments.accountId.equals(accountId) &
          db.supplierPayments.method.equals('CONSIGNMENT'));
    final supplierRows = await supplierQuery.get();
    for (final row in supplierRows) {
      final payment = row.readTable(db.supplierPayments);
      final supplier = row.readTable(db.suppliers);
      movements.add(
        AccountMovement(
          date: payment.date,
          amount: -payment.amount,
          description: 'Pago a proveedor · ${supplier.name}',
        ),
      );
    }

    movements.sort((a, b) => b.date.compareTo(a.date));
    return movements;
  }

  return trigger.asyncMap((_) => load());
});

class CommissionPayment {
  const CommissionPayment({
    required this.date,
    required this.employeeName,
    required this.amount,
  });
  final DateTime date;
  final String employeeName;
  final int amount;
}

/// Historial de pagos de comisión ya registrados — la confirmación de que
/// "sí se descontó" que no se veía en ningún lado antes: fecha, a quién y
/// cuánto, más reciente primero.
final commissionPaymentsHistoryProvider =
    StreamProvider.autoDispose<List<CommissionPayment>>((ref) {
  final db = ref.watch(databaseProvider);
  final trigger = StreamGroup.merge<void>([
    db.select(db.cashMovements).watch().map((_) {}),
    db.select(db.employees).watch().map((_) {}),
  ]);

  Future<List<CommissionPayment>> load() async {
    final rows = await (db.select(db.cashMovements)
          ..where((c) => c.type.equals('COMMISSION_PAYMENT') & c.refType.equals('EMPLOYEE'))
          ..orderBy([(c) => OrderingTerm.desc(c.date)]))
        .get();
    final employees = await db.select(db.employees).get();
    final nameById = {for (final e in employees) e.id: e.name};

    return [
      for (final r in rows)
        CommissionPayment(
          date: r.date,
          employeeName: nameById[r.refId] ?? 'Desconocido',
          amount: -r.amount,
        ),
    ];
  }

  return trigger.asyncMap((_) => load());
});

class PeopleRepository {
  PeopleRepository(this._db);
  final AppDatabase _db;

  Future<int> saveCustomer({
    int? id,
    required String name,
    String? document,
    String? phone,
    String address = '',
  }) async {
    if (id == null) {
      return _db.into(_db.customers).insert(
            CustomersCompanion.insert(
              name: name,
              document: Value(document),
              phone: Value(phone),
              address: Value(address),
            ),
          );
    }
    await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
      CustomersCompanion(
        name: Value(name),
        document: Value(document),
        phone: Value(phone),
        address: Value(address),
      ),
    );
    return id;
  }

  Future<void> setCustomerActive(int id, bool active) async {
    await (_db.update(_db.customers)..where((c) => c.id.equals(id)))
        .write(CustomersCompanion(isActive: Value(active)));
  }

  Future<int> saveEmployee({
    int? id,
    required String name,
    String? document,
    double defaultCommissionRate = 0,
  }) async {
    if (id == null) {
      return _db.into(_db.employees).insert(
            EmployeesCompanion.insert(
              name: name,
              document: Value(document),
              defaultCommissionRate: Value(defaultCommissionRate),
            ),
          );
    }
    await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(
      EmployeesCompanion(
        name: Value(name),
        document: Value(document),
        defaultCommissionRate: Value(defaultCommissionRate),
      ),
    );
    return id;
  }

  Future<void> setEmployeeActive(int id, bool active) async {
    await (_db.update(_db.employees)..where((e) => e.id.equals(id)))
        .write(EmployeesCompanion(isActive: Value(active)));
  }

  /// Registra el pago de comisiones a un vendedor (ej. cada 8 días o
  /// quincena): descuenta caja y hace que el pendiente vuelva a bajar,
  /// en vez de acumularse para siempre.
  Future<void> payCommission({
    required int employeeId,
    required int amount,
    String note = '',
  }) async {
    await _db.into(_db.cashMovements).insert(
          CashMovementsCompanion.insert(
            type: 'COMMISSION_PAYMENT',
            amount: -amount,
            detail: Value(note),
            refType: 'EMPLOYEE',
            refId: employeeId,
          ),
        );
  }

  Future<int> saveSupplier({
    int? id,
    required String name,
    String? document,
    String? phone,
  }) async {
    if (id == null) {
      return _db.into(_db.suppliers).insert(
            SuppliersCompanion.insert(
              name: name,
              document: Value(document),
              phone: Value(phone),
            ),
          );
    }
    await (_db.update(_db.suppliers)..where((s) => s.id.equals(id))).write(
      SuppliersCompanion(name: Value(name), document: Value(document), phone: Value(phone)),
    );
    return id;
  }

  Future<void> setSupplierActive(int id, bool active) async {
    await (_db.update(_db.suppliers)..where((s) => s.id.equals(id)))
        .write(SuppliersCompanion(isActive: Value(active)));
  }

  Future<int> savePaymentAccount({
    int? id,
    required String label,
    String bankName = '',
    String accountNumber = '',
  }) async {
    if (id == null) {
      return _db.into(_db.paymentAccounts).insert(
            PaymentAccountsCompanion.insert(
              label: label,
              bankName: Value(bankName),
              accountNumber: Value(accountNumber),
            ),
          );
    }
    await (_db.update(_db.paymentAccounts)..where((a) => a.id.equals(id))).write(
      PaymentAccountsCompanion(
        label: Value(label),
        bankName: Value(bankName),
        accountNumber: Value(accountNumber),
      ),
    );
    return id;
  }

  Future<void> setPaymentAccountActive(int id, bool active) async {
    await (_db.update(_db.paymentAccounts)..where((a) => a.id.equals(id)))
        .write(PaymentAccountsCompanion(isActive: Value(active)));
  }
}

final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  return PeopleRepository(ref.watch(databaseProvider));
});
