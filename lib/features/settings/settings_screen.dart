import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/backup_service.dart';
import '../../core/providers.dart';

/// Respaldo y restauración de la base de datos — para que una
/// actualización del APK, un cambio de tablet o cualquier imprevisto
/// nunca borre la información del negocio.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _working = false;

  Future<void> _backup() async {
    setState(() => _working = true);
    try {
      await shareBackup(ref.read(databaseProvider));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copia de seguridad lista para enviar.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo hacer la copia: $e')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar copia de seguridad'),
        content: const Text(
          'Esto va a REEMPLAZAR toda la información actual (ventas, '
          'apartados, inventario, todo) con la del archivo que elijas. '
          'Lo que haya cambiado después de esa copia se pierde. '
          '¿Seguro que quieres continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final result = await restoreBackup(ref.read(databaseProvider));
    if (!mounted) return;

    if (!result.success) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Listo'),
        content: const Text(
          'Se restauró la copia de seguridad. Ahora cierra la app '
          'completamente (no solo minimizarla) y vuelve a abrirla para '
          'ver la información restaurada.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Copia de seguridad', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Guarda toda la información del negocio en un archivo '
                    'que puedes enviarte por WhatsApp, correo o Drive. '
                    'Hazlo antes de instalar una actualización de la app, '
                    'así nunca se pierde nada.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _working ? null : _backup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Hacer copia de seguridad'),
                  ),
                  const SizedBox(height: 24),
                  Text('Restaurar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Elige un archivo de copia de seguridad ya guardado '
                    'para volver a esa información. Reemplaza todo lo que '
                    'haya en este momento en la app.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _restore,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Restaurar copia de seguridad'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_working) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
