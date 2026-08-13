import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/catalog_tables.dart';
import 'tables/cash_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/kit_tables.dart';
import 'tables/layaway_tables.dart';
import 'tables/payment_tables.dart';
import 'tables/people_tables.dart';
import 'tables/purchase_tables.dart';
import 'tables/sale_tables.dart';
import 'tables/settings_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    // Catálogo
    Categories,
    Products,
    // Personas
    Customers,
    Employees,
    Suppliers,
    PaymentAccounts,
    // Inventario
    Warehouses,
    Stock,
    ProductLots,
    StockMovements,
    // Kits
    Kits,
    KitComponents,
    // Compras
    Purchases,
    PurchaseItems,
    SupplierPayments,
    // Ventas
    Sales,
    SaleItems,
    SaleItemLotConsumptions,
    SaleReturns,
    // Apartados
    Layaways,
    LayawayItems,
    LayawayReturns,
    // Pagos (multipago / consignación)
    Payments,
    PaymentLines,
    // Caja y gastos
    CashMovements,
    CashSessions,
    ExpenseCategories,
    Expenses,
    FixedAssets,
    // Configuración / login
    AppUser,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // El vendedor de un apartado pasó a ser opcional (antes era
            // obligatorio), igual que ya lo era en Ventas.
            await m.alterTable(TableMigration(layaways));
          }
          if (from < 3) {
            // Comisión predeterminada por vendedor, para no tener que
            // escribirla a mano en cada venta/abono.
            await m.addColumn(employees, employees.defaultCommissionRate);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'muebles_andres.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        // Restricciones de integridad referencial activas siempre.
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });
}
