import 'package:flutter/material.dart';

import 'categories_screen.dart';
import 'products_screen.dart';
import 'stock_screen.dart';

/// Módulo de Inventario: catálogo (productos y categorías) más existencias
/// actuales de cada producto (alimentadas por Compras y descontadas por
/// Ventas/Apartados).
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Existencias'),
              Tab(text: 'Productos'),
              Tab(text: 'Categorías'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            StockScreen(),
            ProductsScreen(),
            CategoriesScreen(),
          ],
        ),
      ),
    );
  }
}
