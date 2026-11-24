import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/ops.dart';
import '../../services/pdf_service.dart';
import '../cotizador/cot_params.dart';

String estadoMp(Rec m) {
  final s = m.n('stock'), mn = m.n('minimo'), mx = m.n('maximo');
  if (s <= 0) return 'Sin stock';
  if (mn > 0 && s <= mn) return 'Bajo mínimo';
  if (mx > 0 && s > mx) return 'Sobre máximo';
  if (mn == 0 && mx == 0) return 'Bajo pedido';
  return 'OK';
}

Color colorEstadoMp(String e) => {'Sin stock': Colors.red, 'Bajo mínimo': Colors.orange, 'Sobre máximo': Colors.blue, 'Bajo pedido': Colors.blueGrey, 'OK': Colors.green}[e] ?? Colors.grey;

class InventarioPage extends StatelessWidget {
  const InventarioPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: PageBody(
        title: 'Inventarios',
        subtitle: 'Materia prima (código de barras) y producto terminado',
        scroll: false,
        child: Column(children: [
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Materia prima'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Entrada por escáner'),
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Producto terminado'),
            Tab(icon: Icon(Icons.business_outlined), text: 'Proveedores'),
            Tab(icon: Icon(Icons.swap_vert), text: 'Movimientos'),
          ]),
          const SizedBox(height: 8),
          const Expanded(child: TabBarView(children: [_MpTab(), _EntradaTab(), _PtTab(), _ProvTab(), _MovTab()])),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Materia prima
class _MpTab extends StatefulWidget {
  const _MpTab();
  @override
  State<_MpTab> createState() => _MpTabState();
}

class _MpTabState extends State<_MpTab> {
  String q = '', filtro = 'Todos';

  Future<void> _editar([Rec? r]) async {
    final k = <String, TextEditingController>{
      for (final e in {'sku': r?.id ?? '', 'descripcion': r?.s('descripcion') ?? '', 'largoMm': r?.s('largoMm') ?? '', 'anchoMm': r?.s('anchoMm') ?? '', 'ect': r?.s('ect') ?? '', 'costoUnitario': r?.s('costoUnitario') ?? '', 'minimo': r?.s('minimo') ?? '', 'maximo': r?.s('maximo') ?? '', 'puntoReorden': r?.s('puntoReorden') ?? '', 'cliente': r?.s('cliente') ?? ''}.entries)
        e.key: TextEditingController(text: e.value == 'null' ? '' : e.value)
    };
    String material = r?.s('material', 'Kraft') ?? 'Kraft', flauta = r?.s('flauta', 'C') ?? 'C';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(r == null ? 'Nueva materia prima' : 'Editar ${r.id}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: ResponsiveGrid(minItemWidth: 160, children: [
                textField(k['sku']!, 'SKU / código de barras *', enabled: r == null),
                textField(k['descripcion']!, 'Descripción *'),
                numField(k['largoMm']!, 'Largo', suffix: 'mm'),
                numField(k['anchoMm']!, 'Ancho', suffix: 'mm'),
                dropdown<String>('Material', material, Catalogos.materiales, (v) => set(() => material = v!)),
                dropdown<String>('Flauta', flauta, Catalogos.flautas, (v) => set(() => flauta = v!)),
                numField(k['ect']!, 'ECT', dec: false),
                numField(k['costoUnitario']!, 'Costo por lámina', prefix: '\$'),
                numField(k['minimo']!, 'Stock mínimo'),
                numField(k['maximo']!, 'Stock máximo'),
                numField(k['puntoReorden']!, 'Punto de reorden'),
                textField(k['cliente']!, 'Cliente / uso'),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar'))],
        ),
      ),
    );
    if (ok != true) return;
    final sku = k['sku']!.text.trim().toUpperCase().replaceAll('/', '-');
    if (sku.isEmpty || k['descripcion']!.text.trim().isEmpty) return toast(context, 'SKU y descripción son obligatorios.', error: true);
    final area = toD(k['largoMm']!.text) * toD(k['anchoMm']!.text) / 1e6;
    final costo = toD(k['costoUnitario']!.text);
    final data = {
      'sku': sku,
      'descripcion': k['descripcion']!.text.trim(),
      'largoMm': toD(k['largoMm']!.text),
      'anchoMm': toD(k['anchoMm']!.text),
      'material': material,
      'flauta': flauta,
      'ect': toD(k['ect']!.text).round(),
      'costoUnitario': costo,
      'precioM2': area > 0 ? costo / area : 0,
      'minimo': toD(k['minimo']!.text),
      'maximo': toD(k['maximo']!.text),
      'puntoReorden': toD(k['puntoReorden']!.text),
      'cliente': k['cliente']!.text.trim(),
      'barcode': sku,
      'unidad': 'HOJA',
      'activo': true,
    };
    try {
      if (r == null) {
        await Db.set('materias_primas', sku, {...data, 'stock': 0, 'reservado': 0}, create: true);
      } else {
        await Db.update('materias_primas', sku, data);
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _ajuste(Rec m) async {
    final real = TextEditingController(text: fmtN(m.n('stock'), 0).replaceAll(',', ''));
    final mot = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ajuste de inventario ${m.id}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [numField(real, 'Existencia física real'), const SizedBox(height: 10), textField(mot, 'Motivo (conteo físico, daño, etc.) *')]),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aplicar'))],
      ),
    );
    if (ok != true) return;
    if (mot.text.trim().isEmpty) return toast(context, 'Indica el motivo.', error: true);
    try {
      await Ops.ajusteMp(sku: m.id, stockReal: toD(real.text), motivo: mot.text.trim());
      Ops.revisarStockBajo(m.id);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RecStream(
      stream: Db.stream('materias_primas', orderBy: 'sku'),
      builder: (c, todas) {
        final valor = todas.fold<double>(0, (a, m) => a + m.n('stock') * m.n('costoUnitario'));
        final alertas = todas.where((m) => ['Sin stock', 'Bajo mínimo'].contains(estadoMp(m)) && (m.n('minimo') > 0 || m.n('stock') <= 0 && m.n('puntoReorden') > 0)).length;
        final lista = todas.where((m) => (filtro == 'Todos' || estadoMp(m) == filtro) && '${m.id} ${m.s('descripcion')} ${m.s('cliente')}'.toLowerCase().contains(q.toLowerCase())).toList();
        return Column(children: [
          ResponsiveGrid(minItemWidth: 200, children: [
            KpiCard(label: 'SKUs de materia prima', value: fmtI(todas.length), icon: Icons.category_outlined),
            KpiCard(label: 'Valor de inventario', value: money(valor, decimals: false), icon: Icons.attach_money, color: Colors.green),
            KpiCard(label: 'Láminas en stock', value: fmtI(todas.fold<double>(0, (a, m) => a + m.n('stock'))), icon: Icons.layers_outlined, color: Colors.indigo),
            KpiCard(label: 'Alertas (sin stock / bajo mín.)', value: '$alertas', icon: Icons.warning_amber, color: Colors.orange),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar por SKU, medida o cliente'), onChanged: (v) => setState(() => q = v))),
            const SizedBox(width: 8),
            SizedBox(width: 170, child: dropdown<String>('Estado', filtro, ['Todos', 'Sin stock', 'Bajo mínimo', 'OK', 'Sobre máximo', 'Bajo pedido'], (v) => setState(() => filtro = v!))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () async => PdfService.imprimir(await PdfService.etiquetas(lista), 'Etiquetas-MP.pdf'), icon: const Icon(Icons.print), label: const Text('Etiquetas')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nueva')),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: lista.isEmpty
                ? const EmptyState('Sin materias primas. Carga los datos iniciales en Administración.')
                : Card(
                    margin: EdgeInsets.zero,
                    child: ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = lista[i];
                        final e = estadoMp(m);
                        return ListTile(
                          dense: true,
                          title: Text('${m.id} · ${m.s('descripcion')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Stock ${fmtI(m.n('stock'))} (reservado ${fmtI(m.n('reservado'))}) · mín ${fmtI(m.n('minimo'))} · máx ${fmtI(m.n('maximo'))} · ${money(m.n('costoUnitario'))}/lámina · valor ${money(m.n('stock') * m.n('costoUnitario'), decimals: false)}'),
                          leading: Icon(Icons.circle, size: 14, color: colorEstadoMp(e)),
                          trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(e, style: TextStyle(color: colorEstadoMp(e), fontWeight: FontWeight.w600, fontSize: 12)),
                            IconButton(tooltip: 'Ajuste', icon: const Icon(Icons.rule), onPressed: () => _ajuste(m)),
                            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(m)),
                          ]),
                        );
                      },
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ Entrada por escáner
class _EntradaTab extends StatefulWidget {
  const _EntradaTab();
  @override
  State<_EntradaTab> createState() => _EntradaTabState();
}

class _EntradaTabState extends State<_EntradaTab> {
  Rec? mp;
  List<Rec> provs = [];
  double tol = 10;
  final cant = TextEditingController(), pedida = TextEditingController(), lote = TextEditingController(), doc = TextEditingController(), costo = TextEditingController();
  String provId = '';
  bool busy = false;
  final recientes = <String>[];

  @override
  void initState() {
    super.initState();
    Db.getAll('proveedores', orderBy: 'nombre').then((v) => setState(() => provs = v));
    Db.get('parametros', 'cotizador').then((r) => setState(() => tol = CotParams.fromMap(r?.d).toleranciaRecepcionPct));
  }

  Future<void> _scan(String raw) async {
    final sku = normalizaBarcode(raw);
    final m = await Db.get('materias_primas', sku);
    if (!mounted) return;
    if (m == null) return toast(context, 'El código $sku no está dado de alta como materia prima.', error: true);
    setState(() {
      mp = m;
      cant.clear();
      pedida.clear();
      costo.text = m.n('costoUnitario') > 0 ? '${m.n('costoUnitario')}' : '';
    });
  }

  Future<void> _guardar() async {
    final m = mp!;
    final q = toD(cant.text);
    if (q <= 0) return toast(context, 'Captura la cantidad recibida.', error: true);
    setState(() => busy = true);
    try {
      final prov = provs.where((p) => p.id == provId).toList();
      final r = await Ops.entradaMp(
        sku: m.id,
        cantidad: q,
        toleranciaPct: tol,
        lote: lote.text.trim(),
        documento: doc.text.trim(),
        proveedorId: provId,
        proveedorNombre: prov.isEmpty ? '' : prov.first.s('nombre'),
        costoUnitario: toD(costo.text) > 0 ? toD(costo.text) : null,
        cantidadPedida: toD(pedida.text) > 0 ? toD(pedida.text) : null,
      );
      Ops.revisarStockBajo(m.id);
      final dentro = r['dentroTolerancia'];
      if (mounted) {
        toast(context, 'Entrada registrada. Nuevo stock: ${fmtI(r['stock'] as num)}${dentro == false ? ' · ⚠ FUERA de la tolerancia ±${tol.toStringAsFixed(0)}% (${fmtN(r['desviacionPct'] as num, 1)}%)' : ''}', error: dentro == false);
        recientes.insert(0, '${m.id} +${fmtI(q)}  (${r['stock'] != null ? 'stock ${fmtI(r['stock'] as num)}' : ''})');
        setState(() {
          mp = null;
          cant.clear();
          pedida.clear();
          lote.clear();
          doc.clear();
        });
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = mp;
    final desv = (toD(pedida.text) > 0) ? (toD(cant.text) - toD(pedida.text)) / toD(pedida.text) * 100 : null;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ScanField(label: 'Escanea el código de barras de la materia prima (o escribe el SKU)', onScan: _scan),
        const SizedBox(height: 12),
        if (m == null)
          const EmptyState('Escanea una etiqueta para registrar la recepción.\nLas etiquetas se imprimen desde la pestaña Materia prima.', icon: Icons.qr_code_scanner)
        else
          SectionCard(
            title: '${m.id} · ${m.s('descripcion')}',
            trailing: Text('Stock actual: ${fmtI(m.n('stock'))}'),
            child: Column(children: [
              ResponsiveGrid(minItemWidth: 200, children: [
                numField(cant, 'Cantidad recibida (láminas) *', onChanged: (_) => setState(() {})),
                numField(pedida, 'Cantidad pedida (OC)', onChanged: (_) => setState(() {}), helper: 'Para validar ±${tol.toStringAsFixed(0)}% del proveedor'),
                textField(lote, 'Lote'),
                textField(doc, 'No. de documento / remisión'),
                numField(costo, 'Costo por lámina', prefix: '\$'),
                dropdown<String>('Proveedor', provId.isEmpty ? null : provId, provs.map((p) => p.id).toList(), (v) => setState(() => provId = v ?? ''), text: (id) => provs.firstWhere((p) => p.id == id).s('nombre')),
              ]),
              if (desv != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Icon(desv.abs() <= tol ? Icons.check_circle : Icons.error, color: desv.abs() <= tol ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Text('Desviación ${fmtN(desv, 1)}% · ${desv.abs() <= tol ? 'dentro de tolerancia' : 'FUERA de tolerancia ±${tol.toStringAsFixed(0)}%'}'),
                  ]),
                ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: [TextButton(onPressed: () => setState(() => mp = null), child: const Text('Cancelar')), FilledButton.icon(onPressed: busy ? null : _guardar, icon: const Icon(Icons.add_box), label: const Text('Agregar al inventario'))])),
            ]),
          ),
        if (recientes.isNotEmpty) ...[const SizedBox(height: 12), SectionCard(title: 'Recibido en esta sesión', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final r in recientes.take(10)) Text(r)]))],
      ]),
    );
  }
}

// ------------------------------------------------------------------ Producto terminado
class _PtTab extends StatefulWidget {
  const _PtTab();
  @override
  State<_PtTab> createState() => _PtTabState();
}

class _PtTabState extends State<_PtTab> {
  String q = '';

  Future<void> _nuevo([Rec? r]) async {
    final sku = TextEditingController(text: r?.id), desc = TextEditingController(text: r?.s('descripcion')), costo = TextEditingController(text: r == null ? '' : '${r.n('costoUnitario')}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r == null ? 'Nuevo producto terminado' : 'Editar ${r.id}'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [textField(sku, 'SKU *', enabled: r == null), const SizedBox(height: 10), textField(desc, 'Descripción *'), const SizedBox(height: 10), numField(costo, 'Costo unitario', prefix: '\$')])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar'))],
      ),
    );
    if (ok != true || sku.text.trim().isEmpty) return;
    final id = sku.text.trim().toUpperCase().replaceAll('/', '-');
    final data = {'sku': id, 'descripcion': desc.text.trim(), 'costoUnitario': toD(costo.text), 'barcode': id};
    if (r == null) {
      await Db.set('productos', id, {...data, 'stock': 0}, create: true);
    } else {
      await Db.update('productos', id, data);
    }
  }

  Future<void> _mov(Rec p, bool entrada) async {
    final cant = TextEditingController(), ref = TextEditingController(), lote = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${entrada ? 'Entrada' : 'Salida'} · ${p.id}'),
        content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [numField(cant, 'Cantidad'), const SizedBox(height: 10), textField(lote, 'Lote'), const SizedBox(height: 10), textField(ref, entrada ? 'Orden de compra / folio' : 'Factura')])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar'))],
      ),
    );
    if (ok != true) return;
    try {
      await Ops.movimientoPt(sku: p.id, cantidad: toD(cant.text), entrada: entrada, lote: lote.text, factura: entrada ? null : ref.text, ordenCompra: entrada ? ref.text : null);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => RecStream(
        stream: Db.stream('productos', orderBy: 'sku'),
        builder: (c, todos) {
          final lista = todos.where((p) => '${p.id} ${p.s('descripcion')}'.toLowerCase().contains(q.toLowerCase())).toList();
          final valor = todos.fold<double>(0, (a, p) => a + p.n('stock') * p.n('costoUnitario'));
          return Column(children: [
            ResponsiveGrid(minItemWidth: 200, children: [
              KpiCard(label: 'SKUs de producto terminado', value: fmtI(todos.length), icon: Icons.inventory_outlined),
              KpiCard(label: 'Piezas en stock', value: fmtI(todos.fold<double>(0, (a, p) => a + p.n('stock'))), icon: Icons.all_inbox, color: Colors.indigo),
              KpiCard(label: 'Valor PT', value: money(valor, decimals: false), icon: Icons.attach_money, color: Colors.green),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar producto'), onChanged: (v) => setState(() => q = v))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: () async => PdfService.imprimir(await PdfService.etiquetas(lista), 'Etiquetas-PT.pdf'), icon: const Icon(Icons.print), label: const Text('Etiquetas')),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _nuevo(), icon: const Icon(Icons.add), label: const Text('Nuevo')),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: lista.isEmpty
                  ? const EmptyState('Sin productos')
                  : Card(
                      margin: EdgeInsets.zero,
                      child: ListView.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = lista[i];
                          return ListTile(
                            dense: true,
                            title: Text('${p.id} · ${p.s('descripcion')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Stock ${fmtI(p.n('stock'))} · costo ${money(p.n('costoUnitario'))} · valor ${money(p.n('stock') * p.n('costoUnitario'), decimals: false)}', style: TextStyle(color: p.n('stock') < 0 ? Colors.red : null)),
                            trailing: Wrap(children: [
                              IconButton(tooltip: 'Entrada', icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => _mov(p, true)),
                              IconButton(tooltip: 'Salida', icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _mov(p, false)),
                              IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _nuevo(p)),
                            ]),
                          );
                        },
                      ),
                    ),
            ),
          ]);
        },
      );
}

// ------------------------------------------------------------------ Proveedores
class _ProvTab extends StatelessWidget {
  const _ProvTab();

  Future<void> _edit(BuildContext context, [Rec? r]) async {
    final k = {for (final e in ['nombre', 'rfc', 'contacto', 'telefono', 'correo', 'condicionPago', 'materiales', 'notas']) e: TextEditingController(text: r?.s(e))};
    final lead = TextEditingController(text: r == null ? '' : '${r.n('leadTimeDias')}');
    final cal = TextEditingController(text: r == null ? '' : '${r.n('calificacion')}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r == null ? 'Nuevo proveedor' : 'Editar proveedor'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: ResponsiveGrid(minItemWidth: 200, children: [
              textField(k['nombre']!, 'Nombre / razón social *'),
              textField(k['rfc']!, 'RFC'),
              textField(k['contacto']!, 'Contacto'),
              textField(k['telefono']!, 'Teléfono'),
              textField(k['correo']!, 'Correo'),
              textField(k['condicionPago']!, 'Condición de pago'),
              numField(lead, 'Lead time (días)', dec: false),
              numField(cal, 'Calificación (1-5)'),
              textField(k['materiales']!, 'Materiales que suministra'),
              textField(k['notas']!, 'Notas'),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar'))],
      ),
    );
    if (ok != true || k['nombre']!.text.trim().isEmpty) return;
    final data = {for (final e in k.entries) e.key: e.value.text.trim(), 'leadTimeDias': toD(lead.text), 'calificacion': toD(cal.text)};
    if (r == null) {
      await Db.add('proveedores', data);
    } else {
      await Db.update('proveedores', r.id, data);
    }
  }

  @override
  Widget build(BuildContext context) => RecStream(
        stream: Db.stream('proveedores', orderBy: 'nombre'),
        builder: (c, l) => Column(children: [
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Nuevo proveedor'))),
          const SizedBox(height: 8),
          Expanded(
            child: l.isEmpty
                ? const EmptyState('Sin proveedores')
                : ListView(children: [
                    for (final p in l)
                      Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(title: Text(p.s('nombre')), subtitle: Text('${p.s('materiales')} · lead time ${fmtI(p.n('leadTimeDias'))} días · ${p.s('condicionPago')} · ★ ${fmtN(p.n('calificacion'), 0)}'), trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, p)))),
                  ]),
          ),
        ]),
      );
}

// ------------------------------------------------------------------ Movimientos
class _MovTab extends StatefulWidget {
  const _MovTab();
  @override
  State<_MovTab> createState() => _MovTabState();
}

class _MovTabState extends State<_MovTab> {
  bool mp = true;
  @override
  Widget build(BuildContext context) => Column(children: [
        Align(alignment: Alignment.centerLeft, child: SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('Materia prima')), ButtonSegment(value: false, label: Text('Producto terminado'))], selected: {mp}, onSelectionChanged: (s) => setState(() => mp = s.first))),
        const SizedBox(height: 8),
        Expanded(
          child: RecStream(
            stream: Db.stream(mp ? 'movimientos_mp' : 'movimientos_pt', orderBy: 'fecha', desc: true, limit: 200),
            builder: (c, l) => l.isEmpty
                ? const EmptyState('Sin movimientos')
                : Card(
                    margin: EdgeInsets.zero,
                    child: ListView.separated(
                      itemCount: l.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = l[i];
                        final tipo = m.s('tipo');
                        final entra = tipo.startsWith('entrada');
                        final fuera = m.dt('fecha') == null ? false : false;
                        return ListTile(
                          dense: true,
                          leading: Icon(entra ? Icons.south_west : (tipo == 'ajuste' ? Icons.rule : Icons.north_east), color: entra ? Colors.green : (tipo == 'ajuste' ? Colors.orange : Colors.red)),
                          title: Text('${m.s('sku')} · ${tipo.replaceAll('_', ' ')} · ${fmtN(m.n('cantidad'), 0)}'),
                          subtitle: Text('${fmtDateTime(m.dt('fecha'))} · ${m.s('usuario')} ${m.s('folio')} ${m.s('lote')} ${m.s('documento')} ${m.s('proveedor')} ${m.s('factura')} ${m.s('motivo')}'.replaceAll(RegExp(r'\s+'), ' ')),
                          trailing: m.d['dentroTolerancia'] == false || fuera ? const Chip(label: Text('Fuera ±10%', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFFFE0E0)) : null,
                        );
                      },
                    ),
                  ),
          ),
        ),
      ]);
}
