import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../inventario/inventario_page.dart' show estadoMp;
import '../mermas/mermas_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final subs = <StreamSubscription>[];
  List<Rec> cots = [], ords = [], clis = [], mps = [], pts = [], mermas = [];
  bool listo = false;

  @override
  void initState() {
    super.initState();
    void sub(Stream<List<Rec>> s, void Function(List<Rec>) f) => subs.add(s.listen((v) {
          if (!mounted) return;
          setState(() {
            f(v);
            listo = true;
          });
        }));
    sub(Db.stream('cotizaciones', orderBy: 'fecha', desc: true, limit: 600), (v) => cots = v);
    sub(Db.stream('ordenes', orderBy: 'createdAt', desc: true, limit: 600), (v) => ords = v);
    sub(Db.stream('clientes'), (v) => clis = v);
    sub(Db.stream('materias_primas'), (v) => mps = v);
    sub(Db.stream('productos'), (v) => pts = v);
    sub(Db.stream('mermas', orderBy: 'fecha', desc: true, limit: 600), (v) => mermas = v);
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  List<DateTime> _meses(int n) {
    final h = DateTime.now();
    return [for (var i = n - 1; i >= 0; i--) DateTime(h.year, h.month - i, 1)];
  }

  @override
  Widget build(BuildContext context) {
    if (!listo) return const Center(child: CircularProgressIndicator());
    final ahora = DateTime.now();
    final ini = inicioMes(ahora);
    final s = Session.I;

    // ---- Ventas / CRM
    final aprobadas = cots.where((c) => [EstadoCot.aprobada, EstadoCot.produccion, EstadoCot.entregada].contains(c.s('estado'))).toList();
    final ventasMes = aprobadas.where((c) => (c.dt('fechaAprobacion') ?? DateTime(2000)).isAfter(ini)).fold<double>(0, (a, c) => a + c.n('subtotal'));
    final pend = cots.where((c) => c.s('estado') == EstadoCot.pendiente).toList();
    final rechazadas = cots.where((c) => c.s('estado') == EstadoCot.rechazada).length;
    final tasaCierre = (aprobadas.length + rechazadas) == 0 ? 0.0 : aprobadas.length / (aprobadas.length + rechazadas) * 100;
    final pipeline = {for (final e in EstadoCot.pipeline) e: cots.where((c) => c.s('estado') == e).length.toDouble()};
    final meses = _meses(6);
    final ventasMeses = [for (final m in meses) aprobadas.where((c) {
          final d = c.dt('fechaAprobacion');
          return d != null && d.year == m.year && d.month == m.month;
        }).fold<double>(0, (a, c) => a + c.n('subtotal'))];

    // ---- Producción
    final enProd = ords.where((o) => o.s('estado') != EstadoOt.entregada).length;
    final entregadas = ords.where((o) => o.s('estado') == EstadoOt.entregada && o.dt('fechaEntregada') != null && o.dt('fechaAprobacion') != null).toList();
    final dias = entregadas.isEmpty ? 0.0 : entregadas.fold<double>(0, (a, o) => a + o.dt('fechaEntregada')!.difference(o.dt('fechaAprobacion')!).inHours / 24) / entregadas.length;
    final conComp = entregadas.where((o) => o.dt('fechaCompromiso') != null).toList();
    final aTiempo = conComp.isEmpty ? 0.0 : conComp.where((o) => !o.dt('fechaEntregada')!.isAfter(o.dt('fechaCompromiso')!.add(const Duration(days: 1)))).length / conComp.length * 100;
    final sats = ords.where((o) => o.n('satisfaccion') > 0).toList();
    final satisf = sats.isEmpty ? 0.0 : sats.fold<double>(0, (a, o) => a + o.n('satisfaccion')) / sats.length;
    final apr = ords.fold<double>(0, (a, o) => a + o.n('aprobadas'));
    final mer = ords.fold<double>(0, (a, o) => a + o.n('mermas'));
    final rendimiento = (apr + mer) == 0 ? 0.0 : apr / (apr + mer) * 100;
    final vendidos = <String, double>{};
    for (final o in ords) {
      final k = o.s('producto');
      if (k.isNotEmpty) vendidos[k] = (vendidos[k] ?? 0) + o.n('cantidad');
    }
    final top = (vendidos.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6);

    // ---- Inventario
    final valMp = mps.fold<double>(0, (a, m) => a + m.n('stock') * m.n('costoUnitario'));
    final valPt = pts.fold<double>(0, (a, p) => a + p.n('stock') * p.n('costoUnitario'));
    final estados = <String, double>{};
    for (final m in mps) {
      final e = estadoMp(m);
      estados[e] = (estados[e] ?? 0) + 1;
    }
    final criticos = mps.where((m) => ['Sin stock', 'Bajo mínimo'].contains(estadoMp(m)) && (m.n('minimo') > 0 || m.n('puntoReorden') > 0)).toList();

    // ---- Flujo de clientes
    final activos = clis.where((c) => c.s('estado') == 'activo').length;
    final prospectos = clis.where((c) => c.s('estado') == 'prospecto').length;
    final perdidos = clis.where((c) => c.s('estado') == 'inactivo').length;
    final nuevosMes = clis.where((c) => (c.dt('fechaAlta') ?? DateTime(2000)).isAfter(ini)).length;
    final perdidosMes = clis.where((c) => c.s('estado') == 'inactivo' && (c.dt('fechaBaja') ?? DateTime(2000)).isAfter(ini)).length;
    final retencion = (activos + perdidos) == 0 ? 0.0 : activos / (activos + perdidos) * 100;
    final enRiesgo = clis.where((c) => c.s('estado') == 'activo' && c.dt('ultimoPedido') != null && ahora.difference(c.dt('ultimoPedido')!).inDays > 90).toList();
    final activosMes = <String, double>{};
    for (final m in meses) {
      final fin = DateTime(m.year, m.month + 1, 1);
      activosMes[fmtMes(m)] = clis.where((c) {
        final alta = c.dt('fechaAlta');
        final baja = c.dt('fechaBaja');
        return c.s('estado') != 'prospecto' && (alta == null || alta.isBefore(fin)) && (baja == null || !baja.isBefore(fin));
      }).length.toDouble();
    }

    return PageBody(
      title: 'Hola, ${s.nombre.split(' ').first}',
      subtitle: 'Indicadores en tiempo real · ${fmtDate(ahora)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ResponsiveGrid(minItemWidth: 230, children: [
          KpiCard(label: 'Ventas del mes (sin IVA)', value: money(ventasMes, decimals: false), icon: Icons.trending_up, color: Colors.green),
          KpiCard(label: 'Cotizaciones pendientes', value: '${pend.length}', hint: money(pend.fold<double>(0, (a, c) => a + c.n('subtotal')), decimals: false), icon: Icons.hourglass_bottom, color: Colors.orange),
          KpiCard(label: 'Tasa de cierre', value: '${fmtN(tasaCierre, 0)}%', icon: Icons.percent, color: Colors.indigo),
          KpiCard(label: 'Órdenes en planta', value: '$enProd', icon: Icons.precision_manufacturing_outlined, color: Colors.deepPurple),
          KpiCard(label: 'Tiempo prom. de entrega', value: entregadas.isEmpty ? '-' : '${fmtN(dias, 1)} días', hint: conComp.isEmpty ? null : '${fmtN(aTiempo, 0)}% a tiempo', icon: Icons.timer_outlined),
          KpiCard(label: 'Rendimiento de materia prima', value: '${fmtN(rendimiento, 1)}%', hint: 'aprobadas vs mermas', icon: Icons.recycling, color: Colors.teal),
          KpiCard(label: 'Satisfacción de clientes', value: sats.isEmpty ? '-' : '${fmtN(satisf, 1)} / 5', hint: '${sats.length} evaluaciones', icon: Icons.star_rate_rounded, color: Colors.amber.shade800),
          KpiCard(label: 'Valor de inventario', value: money(valMp + valPt, decimals: false), hint: 'MP ${money(valMp, decimals: false)} · PT ${money(valPt, decimals: false)}', icon: Icons.warehouse_outlined, color: Colors.blueGrey),
        ]),
        const SizedBox(height: 16),
        Text('Flujo de clientes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ResponsiveGrid(minItemWidth: 200, children: [
          KpiCard(label: 'Clientes activos', value: '$activos', icon: Icons.groups, color: Colors.green),
          KpiCard(label: 'Nuevos este mes', value: '$nuevosMes', icon: Icons.person_add_alt, color: Colors.blue),
          KpiCard(label: 'Perdidos este mes', value: '$perdidosMes', hint: 'Total perdidos: $perdidos', icon: Icons.person_off_outlined, color: Colors.red),
          KpiCard(label: 'Retención', value: '${fmtN(retencion, 0)}%', hint: '$prospectos prospectos', icon: Icons.favorite_outline, color: Colors.pink),
        ]),
        const SizedBox(height: 12),
        ResponsiveGrid(minItemWidth: 420, children: [
          SectionCard(title: 'Clientes activos por mes', child: BarrasChart(activosMes)),
          SectionCard(
            title: 'Clientes en riesgo (sin pedido > 90 días)',
            child: enRiesgo.isEmpty
                ? const Padding(padding: EdgeInsets.all(12), child: Text('Ninguno. ¡Buen trabajo!'))
                : Column(children: [for (final c in enRiesgo.take(8)) ListTile(dense: true, leading: const Icon(Icons.person_search_outlined, color: Colors.orange), title: Text(c.s('nombre')), subtitle: Text('Último pedido: ${fmtDate(c.dt('ultimoPedido'))}'))]),
          ),
          SectionCard(title: 'Ventas por mes (sin IVA)', child: LineaChart([for (final m in meses) fmtMes(m)], ventasMeses)),
          SectionCard(title: 'Pipeline de cotizaciones', child: BarrasChart(pipeline)),
          SectionCard(title: 'Productos / modelos más vendidos (piezas)', child: BarrasChart({for (final e in top) e.key: e.value})),
          SectionCard(title: 'Estado del inventario de materia prima', child: PastelChart(estados)),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Alertas de inventario',
          trailing: TextButton(onPressed: () => context.go('/inventario'), child: const Text('Ver inventario')),
          child: criticos.isEmpty
              ? const Text('Sin alertas de materia prima.')
              : Column(children: [
                  for (final m in criticos.take(10))
                    ListTile(dense: true, leading: Icon(Icons.warning_amber, color: m.n('stock') <= 0 ? Colors.red : Colors.orange), title: Text('${m.id} · ${m.s('descripcion')}', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('Stock ${fmtI(m.n('stock'))} · mínimo ${fmtI(m.n('minimo'))}'), trailing: Text(estadoMp(m))),
                ]),
        ),
      ]),
    );
  }
}
