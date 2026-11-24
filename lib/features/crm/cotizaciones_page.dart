import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/ops.dart';
import '../../services/pdf_service.dart';

/// Pipeline de ventas: Pendiente -> Aprobada -> En Producción -> Entregada.
class CotizacionesPage extends StatefulWidget {
  const CotizacionesPage({super.key});
  @override
  State<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends State<CotizacionesPage> {
  bool kanban = true;
  String q = '';

  Future<void> _aprobar(Rec c) async {
    final f = await showDatePicker(
      context: context,
      helpText: 'Fecha compromiso de entrega',
      initialDate: DateTime.now().add(const Duration(days: 28)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (f == null) return;
    if (!mounted) return;
    final ok = await confirmDialog(context, 'Aprobar ${c.s('folio')}', 'Se generará la Orden Viajera con QR y se liberará a planta.\nCliente: ${c.s('clienteNombre')}\nTotal: ${money(c.n('total'))}', ok: 'Aprobar y generar orden');
    if (!ok) return;
    try {
      final id = await Ops.aprobarCotizacion(c.id, fechaCompromiso: f);
      final o = await Db.get('ordenes', id);
      if (mounted) {
        toast(context, 'Orden ${o?.s('folio')} generada.');
        if (o != null) PdfService.imprimir(await PdfService.ordenViajera(o), 'Orden-${o.s('folio')}.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _rechazar(Rec c) async {
    final m = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rechazar ${c.s('folio')}'),
        content: textField(m, 'Motivo (precio, competencia, etc.)'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rechazar'))],
      ),
    );
    if (ok == true) await Ops.cambiarEstadoCotizacion(c.id, EstadoCot.rechazada, motivo: m.text);
  }

  Future<void> _pdf(Rec c) async {
    final emp = await Db.get('config', 'empresa');
    final bytes = await PdfService.cotizacion(c, {...kEmpresaDefault, ...?emp?.d});
    await PdfService.imprimir(bytes, 'Cotizacion-${c.s('folio')}.pdf');
  }

  Widget _card(Rec c) {
    final e = c.s('estado');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(c.s('folio'), style: const TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text(fmtDate(c.dt('fecha')), style: const TextStyle(fontSize: 11))]),
          Text(c.s('clienteNombre'), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${c.s('producto')} · ${fmtI(c.n('cantidad'))} pzs', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 4),
          Text(money(c.n('total'), decimals: false), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (c.s('ordenFolio').isNotEmpty) Text('Orden ${c.s('ordenFolio')}', style: const TextStyle(fontSize: 11)),
          Wrap(spacing: 2, children: [
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_outlined, size: 20), onPressed: () => _pdf(c)),
            if (e == EstadoCot.pendiente) ...[
              IconButton(visualDensity: VisualDensity.compact, tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => context.go('/cotizador?id=${c.id}')),
              IconButton(visualDensity: VisualDensity.compact, tooltip: 'Aprobar', icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.green), onPressed: () => _aprobar(c)),
              IconButton(visualDensity: VisualDensity.compact, tooltip: 'Rechazar', icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.red), onPressed: () => _rechazar(c)),
            ] else if (c.s('ordenId').isNotEmpty)
              IconButton(visualDensity: VisualDensity.compact, tooltip: 'Ver orden', icon: const Icon(Icons.qr_code_2, size: 20), onPressed: () => context.go('/ordenes')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'CRM · Pipeline de ventas',
      subtitle: 'Seguimiento de cada cotización hasta la entrega',
      scroll: false,
      actions: [
        FilledButton.icon(onPressed: () => context.go('/cotizador'), icon: const Icon(Icons.add), label: const Text('Nueva cotización')),
        SegmentedButton<bool>(segments: const [ButtonSegment(value: true, icon: Icon(Icons.view_kanban_outlined), label: Text('Tablero')), ButtonSegment(value: false, icon: Icon(Icons.list), label: Text('Lista'))], selected: {kanban}, onSelectionChanged: (s) => setState(() => kanban = s.first)),
        SizedBox(width: 220, child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar'), onChanged: (v) => setState(() => q = v.toLowerCase()))),
      ],
      child: RecStream(
        stream: Db.stream('cotizaciones', orderBy: 'fecha', desc: true, limit: 400),
        builder: (c, todas) {
          final lista = todas.where((e) => q.isEmpty || '${e.s('folio')} ${e.s('clienteNombre')} ${e.s('producto')}'.toLowerCase().contains(q)).toList();
          if (lista.isEmpty) return const EmptyState('Aún no hay cotizaciones');
          if (!kanban) {
            return ListView(children: [
              for (final e in lista)
                Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(title: Text('${e.s('folio')} · ${e.s('clienteNombre')}'), subtitle: Text('${e.s('producto')} · ${fmtI(e.n('cantidad'))} pzs · ${fmtDate(e.dt('fecha'))}'), trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [Text(money(e.n('total'))), EstadoChip(e.s('estado'))]), onTap: e.s('estado') == EstadoCot.pendiente ? () => context.go('/cotizador?id=${e.id}') : null)),
            ]);
          }
          final cols = [...EstadoCot.pipeline];
          return Scrollbar(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final est in cols)
                Container(
                  width: 300,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Builder(builder: (_) {
                      final items = lista.where((e) => e.s('estado') == est).toList();
                      final suma = items.fold<double>(0, (a, b) => a + b.n('total'));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [EstadoChip(est), const SizedBox(width: 8), Text('${items.length} · ${money(suma, decimals: false)}', style: const TextStyle(fontSize: 12))]),
                      );
                    }),
                    Expanded(child: ListView(children: [for (final e in lista.where((e) => e.s('estado') == est)) _card(e)])),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}
