import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';

/// Lista de pendientes en calendario: tareas manuales + automáticas (stock bajo, ajustes, órdenes por entregar).
class PendientesPage extends StatefulWidget {
  const PendientesPage({super.key});
  @override
  State<PendientesPage> createState() => _PendientesPageState();
}

class _PendientesPageState extends State<PendientesPage> {
  DateTime foco = DateTime.now();
  DateTime? dia = DateTime.now();
  bool verHechas = false;

  Future<void> _nueva([Rec? r]) async {
    final t = TextEditingController(text: r?.s('titulo')), d = TextEditingController(text: r?.s('detalle'));
    DateTime fecha = r?.dt('fecha') ?? dia ?? DateTime.now();
    String prio = r?.s('prioridad', 'media') ?? 'media';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(r == null ? 'Nuevo pendiente' : 'Editar pendiente'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              textField(t, 'Título *'),
              const SizedBox(height: 10),
              textField(d, 'Detalle', lines: 2),
              const SizedBox(height: 10),
              dropdown<String>('Prioridad', prio, ['alta', 'media', 'baja'], (v) => set(() => prio = v!)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Fecha: ${fmtDate(fecha)}'),
                onPressed: () async {
                  final f = await showDatePicker(context: c, initialDate: fecha, firstDate: DateTime(2024), lastDate: DateTime(2100));
                  if (f != null) set(() => fecha = f);
                },
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar'))],
        ),
      ),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    final data = {'titulo': t.text.trim(), 'detalle': d.text.trim(), 'prioridad': prio, 'fecha': Timestamp.fromDate(DateTime(fecha.year, fecha.month, fecha.day, 12))};
    if (r == null) {
      await Db.add('tareas', {...data, 'estado': 'pendiente', 'origen': 'manual'});
    } else {
      await Db.update('tareas', r.id, data);
    }
  }

  Color _pc(String p) => p == 'alta' ? Colors.red : (p == 'media' ? Colors.orange : Colors.blueGrey);

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Pendientes',
      subtitle: 'Calendario de tareas, reabastecimientos, ajustes y entregas',
      actions: [
        FilledButton.icon(onPressed: () => _nueva(), icon: const Icon(Icons.add_task), label: const Text('Nuevo pendiente')),
        FilterChip(label: const Text('Ver completados'), selected: verHechas, onSelected: (v) => setState(() => verHechas = v)),
      ],
      child: RecStream(
        stream: Db.stream('tareas', orderBy: 'fecha', limit: 500),
        builder: (c, tareas) => RecStream(
          stream: Db.stream('ordenes', orderBy: 'createdAt', desc: true, limit: 200),
          builder: (c2, ordenes) {
            // Entregas por vencer como eventos virtuales
            final entregas = ordenes.where((o) => o.s('estado') != EstadoOt.entregada && o.dt('fechaCompromiso') != null).toList();
            final visibles = tareas.where((t) => verHechas || t.s('estado') != 'hecha').toList();
            bool mismo(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;
            List<Object> eventos(DateTime d) => [
                  ...visibles.where((t) => mismo(t.dt('fecha'), d)),
                  ...entregas.where((o) => mismo(o.dt('fechaCompromiso'), d)),
                ];
            final sel = dia ?? DateTime.now();
            final delDia = eventos(sel);
            final vencidas = visibles.where((t) => t.s('estado') != 'hecha' && (t.dt('fecha')?.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) ?? false)).toList();
            return ResponsiveGrid(minItemWidth: 420, children: [
              SectionCard(
                padding: const EdgeInsets.all(8),
                child: TableCalendar<Object>(
                  locale: 'es_MX',
                  firstDay: DateTime(2024),
                  lastDay: DateTime(2100),
                  focusedDay: foco,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  selectedDayPredicate: (d) => isSameDay(d, dia),
                  eventLoader: eventos,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
                  onDaySelected: (s, f) => setState(() {
                    dia = s;
                    foco = f;
                  }),
                  onPageChanged: (f) => foco = f,
                  calendarStyle: CalendarStyle(markerDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle)),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (vencidas.isNotEmpty)
                  Card(
                    color: Colors.red.shade50,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(leading: const Icon(Icons.alarm, color: Colors.red), title: Text('${vencidas.length} pendiente(s) vencido(s)'), subtitle: Text(vencidas.take(3).map((e) => e.s('titulo')).join(' · '))),
                  ),
                SectionCard(
                  title: 'Pendientes del ${fmtDate(sel)}',
                  child: delDia.isEmpty
                      ? const Padding(padding: EdgeInsets.all(12), child: Text('Nada programado este día.'))
                      : Column(children: [
                          for (final e in delDia)
                            if (e is Rec && e.d.containsKey('titulo'))
                              ListTile(
                                dense: true,
                                leading: Checkbox(value: e.s('estado') == 'hecha', onChanged: (v) => Db.update('tareas', e.id, {'estado': v == true ? 'hecha' : 'pendiente', 'completadaPor': v == true ? Db.uid : null})),
                                title: Text(e.s('titulo'), style: TextStyle(decoration: e.s('estado') == 'hecha' ? TextDecoration.lineThrough : null)),
                                subtitle: Text(e.s('detalle')),
                                trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                                  Icon(Icons.flag, size: 16, color: _pc(e.s('prioridad'))),
                                  if (e.s('ruta').isNotEmpty) IconButton(tooltip: 'Abrir', icon: const Icon(Icons.open_in_new, size: 18), onPressed: () => context.go(e.s('ruta'))),
                                  if (e.s('origen') == 'manual') IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _nueva(e)),
                                  if (e.s('origen') == 'manual') IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => Db.delete('tareas', e.id)),
                                ]),
                              )
                            else if (e is Rec)
                              ListTile(dense: true, leading: const Icon(Icons.local_shipping_outlined), title: Text('Entrega compromiso ${e.s('folio')}'), subtitle: Text('${e.s('clienteNombre')} · ${e.s('estado')}'), trailing: IconButton(icon: const Icon(Icons.open_in_new, size: 18), onPressed: () => context.go('/planta?ot=${e.id}'))),
                        ]),
                ),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}
