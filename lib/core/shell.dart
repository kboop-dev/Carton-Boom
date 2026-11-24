import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'session.dart';
import 'update_checker.dart';
import 'widgets.dart';

class _Item {
  final String ruta, label, modulo;
  final IconData icon;
  const _Item(this.ruta, this.label, this.icon, this.modulo);
}

const _items = [
  _Item('/dashboard', 'Dashboard', Icons.dashboard_outlined, 'dashboard'),
  _Item('/crm', 'CRM · Pipeline', Icons.view_kanban_outlined, 'crm'),
  _Item('/cotizador', 'Cotizador', Icons.calculate_outlined, 'cotizador'),
  _Item('/ect', 'Estudio ECT', Icons.science_outlined, 'cotizador'),
  _Item('/clientes', 'Clientes', Icons.groups_outlined, 'clientes'),
  _Item('/ordenes', 'Órdenes viajeras', Icons.qr_code_2, 'ordenes'),
  _Item('/planta', 'Planta · Checkpoints', Icons.precision_manufacturing_outlined, 'planta'),
  _Item('/inventario', 'Inventarios', Icons.inventory_2_outlined, 'inventario'),
  _Item('/mermas', 'Mermas y calidad', Icons.recycling_outlined, 'mermas'),
  _Item('/pendientes', 'Pendientes', Icons.event_note_outlined, 'pendientes'),
  _Item('/parametros', 'Parámetros', Icons.tune, 'parametros'),
  _Item('/usuarios', 'Usuarios', Icons.manage_accounts_outlined, 'usuarios'),
  _Item('/admin', 'Administración', Icons.admin_panel_settings_outlined, 'admin'),
];

class AppShell extends StatelessWidget {
  final String location;
  final Widget child;
  const AppShell({super.key, required this.location, required this.child});

  Widget _menu(BuildContext context, {bool drawer = false}) {
    final s = Session.I;
    final visibles = _items.where((i) => s.puede(i.modulo)).toList();
    return Container(
      width: 250,
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), children: [
            for (final i in visibles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: ListTile(
                  dense: true,
                  selected: location == i.ruta,
                  selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(.12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(i.icon),
                  title: Text(i.label),
                  onTap: () {
                    if (drawer) Navigator.pop(context);
                    context.go(i.ruta);
                  },
                ),
              ),
          ]),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
          title: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(Roles2.label(s.role)),
          trailing: IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => s.logout()),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: wide ? 16 : 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(children: [
          Image.asset('assets/logo/logo.png', height: 34, errorBuilder: (_, __, ___) => const Icon(Icons.inventory)),
          const SizedBox(width: 10),
          const Text('CARTÓN BOOM', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
        actions: [
          if (!wide) IconButton(tooltip: 'Salir', icon: const Icon(Icons.logout), onPressed: () => Session.I.logout()),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _menu(context, drawer: true))),
      body: Column(children: [
        ValueListenableBuilder<bool>(
          valueListenable: UpdateChecker.I.hayActualizacion,
          builder: (_, v, __) => v
              ? MaterialBanner(
                  content: const Text('Hay una nueva versión de la aplicación disponible.'),
                  leading: const Icon(Icons.system_update_alt),
                  actions: [TextButton(onPressed: UpdateChecker.I.actualizar, child: const Text('ACTUALIZAR AHORA'))],
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Row(children: [
            if (wide) ...[_menu(context), const VerticalDivider(width: 1)],
            Expanded(child: child),
          ]),
        ),
      ]),
    );
  }
}

class Roles2 {
  static String label(String r) => const {
        'admin': 'Administrador',
        'ventas': 'Ventas',
        'almacen': 'Almacén',
        'operador': 'Operador de planta',
        'supervisor': 'Supervisor',
      }[r] ?? r;
}
