import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/pdf_service.dart';

class OrdenesPage extends StatefulWidget {
  const OrdenesPage({super.key});
  @override
  State<OrdenesPage> createState() => _OrdenesPageState();
}

class _OrdenesPageState extends State<OrdenesPage> {
  String filtro = 'Todas', q = '';

  void _qr(Rec o) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(o.s('folio')),
          content: SizedBox(width: 280, height: 300, child: Column(children: [QrImageView(data: o.s('qr', 'CBOT|${o.id}'), size: 240), Text(o.s('clienteNombre'))])),
          actions: [
            TextButton(onPressed: () async => PdfService.imprimir(await PdfService.ordenViajera(o), 'Orden-${o.s('folio')}.pdf'), child: const Text('Imprimir orden (PDF)')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ],
        ),
      );

  void _historial(Rec o) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Trazabilidad ${o.s('folio')}'),
          content: SizedBox(
            width: 520,
            height: 380,
            child: RecStream(
              stream: Db.col('ordenes').doc(o.id).collection('eventos').orderBy('ts').snapshots().map((s) => s.docs.map(Rec.fromSnap).toList()),
              builder: (_, ev) => ev.isEmpty
                  ? const EmptyState('Sin eventos')
                  : ListView(children: [
                      for (final e in ev)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(radius: 14, child: Text('${e.i('checkpoint')}')),
                          title: Text(e.s('estado')),
                          subtitle: Text('${e.s('usuario')} · ${fmtDateTime(e.dt('ts'))}${e.m('datos').isEmpty ? '' : '\n${e.m('datos')}'}'),
                        ),
                    ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Órdenes viajeras',
      subtitle: 'Hoja de ruta de planta con código QR único',
      scroll: false,
      child: RecStream(
        stream: Db.stream('ordenes', orderBy: 'createdAt', desc: true, limit: 300),
        builder: (c, todas) {
          final lista = todas.where((o) => (filtro == 'Todas' || o.s('estado') == filtro) && '${o.s('folio')} ${o.s('clienteNombre')} ${o.s('producto')}'.toLowerCase().contains(q.toLowerCase())).toList();
          return Column(children: [
            Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar orden'), onChanged: (v) => setState(() => q = v))),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: dropdown<String>('Estado', filtro, ['Todas', ...EstadoOt.flujo], (v) => setState(() => filtro = v!))),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: lista.isEmpty
                  ? const EmptyState('No hay órdenes. Se generan al aprobar una cotización en el CRM.')
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final o = lista[i];
                        final cp = EstadoOt.checkpoint[o.s('estado')] ?? 0;
                        return Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(o.s('folio'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(width: 10),
                                EstadoChip(o.s('estado')),
                                const Spacer(),
                                Text('Compromiso: ${fmtDate(o.dt('fechaCompromiso'))}', style: const TextStyle(fontSize: 12)),
                              ]),
                              Text('${o.s('clienteNombre')} · ${o.s('producto')} · ${fmtI(o.n('cantidad'))} pzs'),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: cp / 5, minHeight: 6, borderRadius: BorderRadius.circular(4)),
                              Text('Checkpoint $cp/5 · aprobadas ${fmtI(o.n('aprobadas'))} · mermas ${fmtI(o.n('mermas'))}', style: const TextStyle(fontSize: 11)),
                              Wrap(spacing: 6, children: [
                                TextButton.icon(onPressed: () => _qr(o), icon: const Icon(Icons.qr_code_2), label: const Text('QR / PDF')),
                                TextButton.icon(onPressed: () => context.go('/planta?ot=${o.id}'), icon: const Icon(Icons.precision_manufacturing_outlined), label: const Text('Ir a planta')),
                                TextButton.icon(onPressed: () => _historial(o), icon: const Icon(Icons.history), label: const Text('Trazabilidad')),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
