import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../audit/audit_screen.dart';
import '../auth/login_screen.dart';
import '../expenses/expenses_screen.dart';
import '../finance/finance_screen.dart';
import '../inventory/inventory_screen.dart';
import '../kits/kits_screen.dart';
import '../layaways/layaways_screen.dart';
import '../people/commissions_screen.dart';
import '../people/payment_accounts_screen.dart';
import '../people/suppliers_screen.dart';
import '../purchases/purchases_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sales_screen.dart';
import '../settings/settings_screen.dart';
import 'home_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

/// Shell principal de la app: barra de navegación lateral (apta para
/// tablet en horizontal) + contenido del módulo seleccionado.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  static final List<_Destination> _destinations = [
    _Destination('Inicio', Icons.dashboard_outlined, (_) => const HomeScreen()),
    _Destination(
      'Ventas',
      Icons.point_of_sale_outlined,
      (_) => const SalesScreen(),
    ),
    _Destination(
      'Apartados',
      Icons.event_available_outlined,
      (_) => const LayawaysScreen(),
    ),
    _Destination(
      'Kits',
      Icons.weekend_outlined,
      (_) => const KitsScreen(),
    ),
    _Destination(
      'Inventario',
      Icons.inventory_2_outlined,
      (_) => const InventoryScreen(),
    ),
    _Destination(
      'Compras',
      Icons.local_shipping_outlined,
      (_) => const PurchasesScreen(),
    ),
    _Destination(
      'Proveedores',
      Icons.handshake_outlined,
      (_) => const SuppliersScreen(),
    ),
    _Destination(
      'Consignaciones',
      Icons.account_balance_outlined,
      (_) => const PaymentAccountsScreen(),
    ),
    _Destination(
      'Comisiones',
      Icons.percent_outlined,
      (_) => const CommissionsScreen(),
    ),
    _Destination(
      'Gastos',
      Icons.receipt_long_outlined,
      (_) => const ExpensesScreen(),
    ),
    _Destination(
      'Análisis',
      Icons.bar_chart_outlined,
      (_) => const ReportsScreen(),
    ),
    _Destination(
      'Finanzas',
      Icons.account_balance_wallet_outlined,
      (_) => const FinanceScreen(),
    ),
    _Destination(
      'Auditoría',
      Icons.fact_check_outlined,
      (_) => const AuditScreen(),
    ),
    _Destination(
      'Ajustes',
      Icons.settings_outlined,
      (_) => const SettingsScreen(),
    ),
  ];

  void _logout() {
    ref.read(isLoggedInProvider.notifier).state = false;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: Row(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: IntrinsicHeight(
                child: NavigationRail(
                  extended: wide,
                  minExtendedWidth: 200,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.chair_alt, size: 32),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IconButton(
                          tooltip: 'Cerrar sesión',
                          icon: const Icon(Icons.logout),
                          onPressed: _logout,
                        ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                for (final d in _destinations) Builder(builder: d.builder),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
