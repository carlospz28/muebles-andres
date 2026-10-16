import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/setup_screen.dart';
import 'features/home/home_shell.dart';

class MueblesAndresApp extends ConsumerWidget {
  const MueblesAndresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Muebles Omar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _AuthGate(),
    );
  }
}

/// Decide con qué pantalla arrancar: configuración inicial (primera vez),
/// login (siempre, cada vez que se abre la app) o la app ya autenticada.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(isLoggedInProvider);
    if (loggedIn) return const HomeShell();

    return FutureBuilder<bool>(
      future: ref.read(authServiceProvider).hasUser(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data! ? const LoginScreen() : const SetupScreen();
      },
    );
  }
}
