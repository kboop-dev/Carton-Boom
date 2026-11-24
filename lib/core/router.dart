import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_page.dart';
import '../features/admin/parametros_page.dart';
import '../features/admin/usuarios_page.dart';
import '../features/auth/login_page.dart';
import '../features/cotizador/cotizador_page.dart';
import '../features/cotizador/estudio_ect_page.dart';
import '../features/crm/clientes_page.dart';
import '../features/crm/cotizaciones_page.dart';
import '../features/crm/ordenes_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/inventario/inventario_page.dart';
import '../features/mermas/mermas_page.dart';
import '../features/pendientes/pendientes_page.dart';
import '../features/planta/planta_page.dart';
import 'session.dart';
import 'shell.dart';

/// Ruta -> módulo de permisos.
const _modulo = {
  '/dashboard': 'dashboard',
  '/cotizador': 'cotizador',
  '/ect': 'cotizador',
  '/crm': 'crm',
  '/clientes': 'clientes',
  '/ordenes': 'ordenes',
  '/planta': 'planta',
  '/inventario': 'inventario',
  '/mermas': 'mermas',
  '/pendientes': 'pendientes',
  '/parametros': 'parametros',
  '/usuarios': 'usuarios',
  '/admin': 'admin',
};

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  refreshListenable: Session.I,
  redirect: (context, state) {
    final s = Session.I;
    final loc = state.uri.path;
    if (s.loading) return loc == '/cargando' ? null : '/cargando';
    if (!s.loggedIn) return loc == '/login' ? null : '/login';
    if (!s.active) return loc == '/pendiente' ? null : '/pendiente';
    if (loc == '/login' || loc == '/pendiente' || loc == '/cargando' || loc == '/') return '/dashboard';
    final m = _modulo[loc];
    if (m != null && !s.puede(m)) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(path: '/cargando', builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(path: '/pendiente', builder: (_, __) => const PendientePage()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
        GoRoute(path: '/cotizador', builder: (_, s) => CotizadorPage(cotizacionId: s.uri.queryParameters['id'])),
        GoRoute(path: '/ect', builder: (_, __) => const EstudioEctPage()),
        GoRoute(path: '/crm', builder: (_, __) => const CotizacionesPage()),
        GoRoute(path: '/clientes', builder: (_, __) => const ClientesPage()),
        GoRoute(path: '/ordenes', builder: (_, __) => const OrdenesPage()),
        GoRoute(path: '/planta', builder: (_, s) => PlantaPage(ordenInicial: s.uri.queryParameters['ot'])),
        GoRoute(path: '/inventario', builder: (_, __) => const InventarioPage()),
        GoRoute(path: '/mermas', builder: (_, __) => const MermasPage()),
        GoRoute(path: '/pendientes', builder: (_, __) => const PendientesPage()),
        GoRoute(path: '/parametros', builder: (_, __) => const ParametrosPage()),
        GoRoute(path: '/usuarios', builder: (_, __) => const UsuariosPage()),
        GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
      ],
    ),
  ],
);
