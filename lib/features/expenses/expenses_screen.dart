import 'package:flutter/material.dart';

import 'expense_categories_screen.dart';
import 'expenses_list_screen.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gastos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gastos'),
              Tab(text: 'Categorías'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ExpensesListScreen(),
            ExpenseCategoriesScreen(),
          ],
        ),
      ),
    );
  }
}
