import 'package:flutter/material.dart';

/// Tema visual único de la app. Pensado para tablet en horizontal: tipografía
/// y objetivos táctiles grandes, alto contraste, sin depender de hover.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF2E5E4E); // verde madera oscuro
  static const Color accent = Color(0xFFC8862B); // ámbar/madera clara
  static const Color danger = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D32);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ),
      // Las pestañas (TabBar) siempre viven dentro de un AppBar de fondo
      // oscuro (verde), así que necesitan colores claros explícitos o el
      // texto no se distingue.
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        labelStyle: TextStyle(fontWeight: FontWeight.bold),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(scheme.surfaceContainerHigh),
      ),
    );
  }
}

/// Colores de estado reutilizables (chips de estado en listados).
class StatusColors {
  StatusColors._();

  static const Color pending = Color(0xFF9E7B0E);
  static const Color confirmed = Color(0xFF2E7D32);
  static const Color cancelled = Color(0xFFB3261E);
  static const Color info = Color(0xFF1565C0);
}
