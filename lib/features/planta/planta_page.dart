import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/ops.dart';

/// ERP de planta: 5 checkpoints por escaneo de QR. Pantalla de alto contraste y botones grandes.
class PlantaPage extends StatefulWidget {
  final String? ordenInicial;
  const PlantaPage({super.key, this.ordenInicial});
  @override
  State<PlantaPage> createState() => _PlantaPageState();
}

class _PlantaPageState extends State<PlantaPage> {
  String? sel;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    sel = widget.ordenInicial;
  }

  @override
  void didUpdateWidget(covariant PlantaPage old) {
    super.didUpdateWidget(old);
    if (widget.ordenInicial != null && widget.ordenInicial != old.ordenInicial) sel = widget.ordenInicial;
  }

  Future<void> _escaneo(String raw) async {
    final txt = normalizaQr(raw);
    var o = await Db.get('ordenes', txt);
    if (o == null) {
      final q = await Db.col('ordenes').where('folio', isEqualTo: txt.toUpperCase()).limit(1).get();
      if (q.docs.isNotEmpty) o = Rec.fromSnap(q.docs.first);
    }
    if (!mounted) return;
    if (o == null) return toast(context, 'No se encontró la orden "$raw".', error: true);
    setState(() => sel = o!.id);
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => busy = true);
    try {
      await f();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---- CP1
  Future<void> _cp1(Rec o) async {
    final mps = await Db.getAll('materias_primas', orderBy: 'sku');
    final specs = o.m('specs');
    String sku = o.s('laminaSku');
    if (sku.isEmpty) {
      final bom = (await Db.getAll('bom')).where((b) => b.s('skuPt') == o.s('productoSku'));
      if (bom.isNotEmpty) sku = bom.first.s('skuMp');
    }
    final lam = TextEditingController(text: '${(specs['laminasReq'] is num ? (specs['laminasReq'] as num).round() : o.i('cantidad'))}');
    String? elegido = sku.isEmpty ? null : sku;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Checkpoint 1 · Despacho de materia prima'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RecPicker(
                label: 'Lámina entregada (SKU / medida)',
                items: mps,
                initial: elegido,
                text: (r) => '${r.id} · ${r.s('descripcion')} · stock ${fmtI(r.n('stock') - r.n('reservado'))}',
                onSelected: (r) => set(() => elegido = r.id),
              ),
              const SizedBox(height: 12),
              numField(lam, 'Láminas enviadas a planta', dec: false, suffix: 'láminas'),
              const SizedBox(height: 8),
              Text('Sugeridas por cotización: ${specs['laminasReq'] ?? '-'}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('MATERIA PRIMA ASIGNADA'))],
        ),
      ),
    );
    if (ok != true) return;
    if (elegido == null) return toast(context, 'Selecciona la lámina.', error: true);
    await _run(() => Ops.cp1AsignarMp(ordenId: o.id, sku: elegido!, laminas: toD(lam.text)), 'Materia prima asignada.');
  }

  // ---- CP3
  Future<void> _cp3(Rec o) async {
    final ap = TextEditingController();
    final me = TextEditingController();
    final causa = TextEditingController();
    String tipo = 'Producción';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Checkpoint 3 · Inspección de calidad'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Solicitadas: ${fmtI(o.n('cantidad'))} · láminas asignadas: ${fmtI(o.n('laminasAsignadas') - o.n('laminasConsumidas'))}'),
              const SizedBox(height: 12),
              TextField(controller: ap, autofocus: true, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), decoration: const InputDecoration(labelText: 'Cajas aprobadas')),
              const SizedBox(height: 12),
              TextField(controller: me, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), decoration: const InputDecoration(labelText: 'Mermas / desperdicio')),
              ExpansionTile(
                title: const Text('Causa de la merma (opcional)'),
                tilePadding: EdgeInsets.zero,
                children: [dropdown<String>('Tipo', tipo, Catalogos.tiposMerma, (v) => set(() => tipo = v!)), const SizedBox(height: 8), textField(causa, 'Observaciones')],
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('REGISTRAR'))],
        ),
      ),
    );
    if (ok != true) return;
    final a = int.tryParse(ap.text.trim()), m = int.tryParse(me.text.trim());
    if (a == null || m == null) return toast(context, 'Captura ambos números (puede ser 0).', error: true);
    setState(() => busy = true);
    try {
      final falta = await Ops.cp3Calidad(ordenId: o.id, aprobadas: a, mermas: m, causa: causa.text, tipoMerma: tipo);
      final skuMp = o.s('laminaSku');
      if (skuMp.isNotEmpty) Ops.revisarStockBajo(skuMp);
      if (!mounted) return;
      toast(context, 'Calidad registrada. Inventario actualizado.');
      if (falta) {
        final faltante = o.n('cantidad') - o.n('aprobadas') - a;
        final sol = await confirmDialog(context, 'Faltan piezas', 'Aprobadas ${a + o.i('aprobadas')} < solicitadas ${fmtI(o.n('cantidad'))} (faltan ${fmtI(faltante)}).\n\n¿Solicitar láminas de ajuste al almacén?', ok: 'Sí, solicitar');
        if (sol) {
          await Ops.solicitarAjuste(ordenId: o.id, folio: o.s('folio'), sku: o.s('laminaSku'), laminas: faltante, cliente: o.s('clienteNombre'));
          if (mounted) toast(context, 'Solicitud enviada al almacén (también aparece en Pendientes).');
        }
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cp5(Rec o) async {
    final prods = await Db.getAll('productos', orderBy: 'sku');
    String? sku = o.s('productoSku').isEmpty ? null : o.s('productoSku');
    final lote = TextEditingController(text: o.s('folio'));
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Checkpoint 5 · Producto terminado'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Ingresarán ${fmtI(o.n('aprobadas'))} piezas al almacén de producto terminado.'),
              const SizedBox(height: 10),
              RecPicker(label: 'Producto terminado (opcional)', items: prods, initial: sku, text: (r) => '${r.id} · ${r.s('descripcion')}', onSelected: (r) => set(() => sku = r.id)),
              const SizedBox(height: 10),
              textField(lote, 'Lote'),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('LISTO PARA ENTREGA'))],
        ),
      ),
    );
    if (ok == true) await _run(() => Ops.cp5Listo(ordenId: o.id, productoSku: sku, lote: lote.text), 'Pedido listo para entrega.');
  }

  Future<void> _entregar(Rec o) async {
    final fac = TextEditingController();
    final tr = TextEditingController();
    int sat = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Entregar ${o.s('folio')}'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              textField(fac, 'Factura / remisión'),
              const SizedBox(height: 10),
              textField(tr, o.m('specs')['clienteRecoge'] == false ? 'Transportista' : 'Recoge (nombre)'),
              const SizedBox(height: 12),
              const Text('Satisfacción del cliente (opcional)'),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 1; i <= 5; i++) IconButton(iconSize: 34, icon: Icon(i <= sat ? Icons.star : Icons.star_border, color: Colors.amber), onPressed: () => set(() => sat = i)),
              ]),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('CONFIRMAR ENTREGA'))],
        ),
      ),
    );
    if (ok == true) await _run(() => Ops.entregar(ordenId: o.id, factura: fac.text, transportista: tr.text, satisfaccion: sat == 0 ? null : sat), 'Pedido entregado.');
  }

  Widget _big(String label, IconData icon, VoidCallback f, {Color? color}) => SizedBox(
        width: double.infinity,
        height: 76,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          onPressed: busy ? null : f,
          icon: Icon(icon, size: 30),
          label: Text(label),
        ),
      );

  Widget _panel(Rec o) {
    final e = o.s('estado');
    final cp = EstadoOt.checkpoint[e] ?? 0;
    const nombres = ['Materia prima', 'Impresión / corte', 'Calidad', 'Armado', 'Entrega'];
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(o.s('folio'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          EstadoChip(e),
          const Spacer(),
          IconButton(tooltip: 'Cerrar', onPressed: () => setState(() => sel = null), icon: const Icon(Icons.close)),
        ]),
        Text('${o.s('clienteNombre')} · ${o.s('producto')}', style: const TextStyle(fontSize: 18)),
        Text('Solicitadas ${fmtI(o.n('cantidad'))} · aprobadas ${fmtI(o.n('aprobadas'))} · mermas ${fmtI(o.n('mermas'))} · láminas asignadas ${fmtI(o.n('laminasAsignadas'))} (${o.s('laminaSku', 'sin SKU')})'),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Column(children: [
                CircleAvatar(radius: 16, backgroundColor: cp > i + 1 || (cp == i + 1 && e == EstadoOt.entregada) ? Colors.green : (cp == i + 1 ? Theme.of(context).colorScheme.primary : Colors.grey.shade300), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                Text(nombres[i], style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        if (o.b('requiereAjuste') && e == EstadoOt.calidad)
          Card(color: Colors.orange.shade50, child: ListTile(leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text('Faltan ${fmtI(o.n('faltante'))} piezas para completar el pedido'), trailing: FilledButton(onPressed: () async {
                await _run(() => Ops.solicitarAjuste(ordenId: o.id, folio: o.s('folio'), sku: o.s('laminaSku'), laminas: o.n('faltante'), cliente: o.s('clienteNombre')).then((_) {}), 'Solicitud de ajuste enviada.');
              }, child: const Text('Solicitar láminas de ajuste')))),
        if (e == EstadoOt.pendienteMp) _big('MATERIA PRIMA ASIGNADA', Icons.inventory_2, () => _cp1(o)),
        if (e == EstadoOt.mpAsignada) _big('EN IMPRESIÓN / CORTE', Icons.print, () => _run(() => Ops.cp2Impresion(o.id), 'Orden en impresión / corte.')),
        if (e == EstadoOt.impresion) ...[
          _big('REGISTRAR CALIDAD (APROBADAS / MERMAS)', Icons.fact_check, () => _cp3(o), color: Colors.teal),
          const SizedBox(height: 8),
          const Text('Si la máquina se detiene a ajustar tinta o calibrar, la orden se mantiene en este estado.', style: TextStyle(fontSize: 12)),
        ],
        if (e == EstadoOt.calidad) _big('EN ARMADO MANUAL', Icons.handyman, () => _run(() => Ops.cp4Armado(o.id), 'Orden en armado manual.')),
        if (e == EstadoOt.armado) _big('PEDIDO FINALIZADO', Icons.task_alt, () => _run(() => Ops.cp4Finalizar(o.id), 'Pedido finalizado.'), color: Colors.green),
        if (e == EstadoOt.finalizado) _big('LISTO PARA ENTREGA', Icons.local_shipping, () => _cp5(o), color: Colors.indigo),
        if (e == EstadoOt.listo) _big('REGISTRAR ENTREGA', Icons.handshake, () => _entregar(o), color: Colors.green),
        if (e == EstadoOt.entregada) const ListTile(leading: Icon(Icons.verified, color: Colors.green), title: Text('Pedido entregado')),
      ]),
    );
  }

  Widget _ajustes() => RecStream(
        stream: Db.stream('solicitudes_ajuste', orderBy: 'createdAt', desc: true, limit: 50),
        builder: (c, s) {
          final pend = s.where((e) => e.s('estado') == 'Pendiente').toList();
          if (pend.isEmpty) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              title: 'Solicitudes de láminas de ajuste (Almacén)',
              child: Column(children: [
                for (final r in pend)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_box_outlined),
                    title: Text('${r.s('folio')} · ${fmtI(r.n('laminas'))} láminas de ${r.s('sku')}'),
                    subtitle: Text('${r.s('cliente')} · pide ${r.s('solicitante')}'),
                    trailing: FilledButton(onPressed: busy ? null : () => _run(() => Ops.atenderAjuste(r.id), 'Láminas de ajuste entregadas.'), child: const Text('Entregar')),
                  ),
              ]),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Planta · Checkpoints de producción',
      subtitle: 'Escanea el QR de la Orden Viajera (lector USB, Bluetooth o cámara)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ScanField(label: 'Escanear QR de la orden o escribir folio (OT-2026-0001)', onScan: _escaneo),
        const SizedBox(height: 12),
        _ajustes(),
        if (sel != null)
          StreamBuilder<Rec?>(
            stream: Db.docStream('ordenes', sel!),
            builder: (c, s) => s.hasData && s.data != null ? _panel(s.data!) : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          )
        else
          RecStream(
            stream: Db.stream('ordenes', orderBy: 'createdAt', desc: true, limit: 200),
            builder: (c, todas) {
              final act = todas.where((o) => o.s('estado') != EstadoOt.entregada).toList();
              if (act.isEmpty) return const EmptyState('No hay órdenes en proceso');
              return ResponsiveGrid(minItemWidth: 320, children: [
                for (final o in act)
                  InkWell(
                    onTap: () => setState(() => sel = o.id),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Text(o.s('folio'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const Spacer(), EstadoChip(o.s('estado'))]),
                          Text(o.s('clienteNombre'), style: const TextStyle(fontSize: 16)),
                          Text('${o.s('producto')} · ${fmtI(o.n('cantidad'))} pzs'),
                          Text('Compromiso: ${fmtDate(o.dt('fechaCompromiso'))}', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]);
            },
          ),
      ]),
    );
  }
}
