import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/ops.dart';
import '../../services/pdf_service.dart';
import 'cot_engine.dart';
import 'cot_params.dart';

class CotizadorPage extends StatefulWidget {
  final String? cotizacionId;
  const CotizadorPage({super.key, this.cotizacionId});
  @override
  State<CotizadorPage> createState() => _CotizadorPageState();
}

class _CotizadorPageState extends State<CotizadorPage> {
  CotParams params = CotParams();
  List<Rec> clientes = [], precios = [], mps = [], productos = [];
  List<Map<String, dynamic>> ect = [];
  CotInput inp = CotInput();
  final c = <String, TextEditingController>{};
  TextEditingController t(String k) => c.putIfAbsent(k, () => TextEditingController());

  bool loaded = false, saving = false;
  String? cotId, cotFolio;
  String clienteId = '', clienteNombre = '', laminaSku = '';
  double precioFijo = 0;
  String tipo = TiposCaja.crr, material = 'Kraft', flauta = 'C', acabado = 'Pegada';
  bool entarimado = true, prorratear = true, recoge = true, cobrarSobrante = true;
  CotResult? res;
  List<Map<String, dynamic>> escalas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CotizadorPage old) {
    super.didUpdateWidget(old);
    if (old.cotizacionId != widget.cotizacionId) _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      Db.get('parametros', 'cotizador'),
      Db.getAll('clientes', orderBy: 'nombre'),
      Db.getAll('precios_carton'),
      Db.getAll('catalogo_ect'),
      Db.getAll('materias_primas'),
      Db.getAll('productos'),
    ]);
    params = CotParams.fromMap((r[0] as Rec?)?.d);
    clientes = (r[1] as List<Rec>).where((x) => x.s('estado') != 'inactivo').toList();
    precios = r[2] as List<Rec>;
    ect = (r[3] as List<Rec>).map((e) => e.d).toList();
    mps = r[4] as List<Rec>;
    productos = r[5] as List<Rec>;
    cotId = widget.cotizacionId;
    if (cotId != null) {
      final cot = await Db.get('cotizaciones', cotId!);
      if (cot != null) {
        cotFolio = cot.s('folio');
        _fill(CotInput.fromMap(cot.m('input')));
      }
    } else {
      t('margen').text = params.margenDefaultPct.toStringAsFixed(0);
      t('cantidad').text = '1000';
      t('ect').text = '23';
      t('ppl').text = '1';
      _autoPrecio();
    }
    loaded = true;
    if (mounted) {
      setState(() {});
      _recalc();
    }
  }

  void _fill(CotInput i) {
    clienteId = i.clienteId;
    clienteNombre = i.clienteNombre;
    t('producto').text = i.producto;
    t('codigo').text = i.codigoProducto;
    tipo = i.tipo;
    material = i.material;
    flauta = i.flauta;
    acabado = i.acabado;
    entarimado = i.entarimado;
    prorratear = i.prorratearHerramental;
    recoge = i.clienteRecoge;
    cobrarSobrante = i.cobrarSobrante;
    laminaSku = i.laminaAlmacenSku;
    precioFijo = i.precioLaminaFijo;
    String s(num v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
    t('largo').text = s(i.largo);
    t('ancho').text = s(i.ancho);
    t('alto').text = s(i.alto);
    t('cantidad').text = s(i.cantidad);
    t('ect').text = s(i.ect);
    t('ppl').text = '${i.piezasPorLamina}';
    t('lamL').text = i.laminaLargoCm == null ? '' : s(i.laminaLargoCm!);
    t('lamA').text = i.laminaAnchoCm == null ? '' : s(i.laminaAnchoCm!);
    t('precioM2').text = s(i.precioM2);
    for (var k = 0; k < 4; k++) {
      t('t${k}c').text = k < i.tintas.length ? s(i.tintas[k].cobertura) : '';
      t('t${k}p').text = k < i.tintas.length ? s(i.tintas[k].precioKg) : '';
    }
    t('barnizPct').text = s(i.barnizPct);
    t('barnizPrecio').text = s(i.barnizPrecioKg);
    t('cliche').text = s(i.costoCliche);
    t('suaje').text = s(i.costoSuaje);
    t('monto').text = s(i.montoTransportista);
    t('margen').text = s(i.margenPct);
    t('descExtra').text = s(i.descuentoExtraPct);
    t('notas').text = i.notas;
  }

  void _autoPrecio() {
    for (final p in precios) {
      if (p.s('material') == material && p.s('flauta') == flauta) {
        final v = p.n('precioM2');
        t('precioM2').text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
        return;
      }
    }
  }

  void _read() {
    inp = CotInput()
      ..clienteId = clienteId
      ..clienteNombre = clienteNombre
      ..producto = t('producto').text.trim()
      ..codigoProducto = t('codigo').text.trim()
      ..tipo = tipo
      ..largo = toD(t('largo').text)
      ..ancho = toD(t('ancho').text)
      ..alto = toD(t('alto').text)
      ..cantidad = toD(t('cantidad').text).round()
      ..material = material
      ..flauta = flauta
      ..ect = toD(t('ect').text).round()
      ..laminaLargoCm = toD(t('lamL').text) > 0 ? toD(t('lamL').text) : null
      ..laminaAnchoCm = toD(t('lamA').text) > 0 ? toD(t('lamA').text) : null
      ..piezasPorLamina = max(1, toD(t('ppl').text, 1).round())
      ..tintas = [for (var k = 0; k < 4; k++) TintaIn(toD(t('t${k}c').text), toD(t('t${k}p').text))]
      ..barnizPct = toD(t('barnizPct').text)
      ..barnizPrecioKg = toD(t('barnizPrecio').text)
      ..acabado = acabado
      ..entarimado = entarimado
      ..costoCliche = toD(t('cliche').text)
      ..costoSuaje = toD(t('suaje').text)
      ..prorratearHerramental = prorratear
      ..precioM2 = toD(t('precioM2').text)
      ..precioLaminaFijo = laminaSku.isEmpty ? 0 : precioFijo
      ..laminaAlmacenSku = laminaSku
      ..cobrarSobrante = cobrarSobrante
      ..clienteRecoge = recoge
      ..montoTransportista = toD(t('monto').text)
      ..margenPct = toD(t('margen').text, params.margenDefaultPct)
      ..descuentoExtraPct = toD(t('descExtra').text)
      ..notas = t('notas').text.trim();
  }

  void _recalc() {
    if (!loaded) return;
    _read();
    final peso = CotEngine.pesoG10x10(ect, flauta, material, inp.ect);
    final r = CotEngine.calcular(inp, params, pesoG10x10: peso);
    final esc = <Map<String, dynamic>>[];
    if (r.ok) {
      final qs = <int>{inp.cantidad};
      for (final s in t('escalas').text.split(RegExp(r'[,; ]+'))) {
        final q = int.tryParse(s.replaceAll('.', ''));
        if (q != null && q > 0) qs.add(q);
      }
      final lista = qs.toList()..sort();
      for (final q in lista) {
        final i2 = inp.copy()..cantidad = q;
        final r2 = CotEngine.calcular(i2, params, pesoG10x10: peso);
        if (r2.ok) esc.add({'cantidad': q, 'precioUnitConFlete': r2.precioUnitConFlete, 'total': r2.subtotal, 'margen': r2.margenReal, 'permitido': r2.permitido});
      }
    }
    setState(() {
      res = r;
      escalas = esc;
    });
  }

  Future<void> _guardar() async {
    _recalc();
    final r = res!;
    if (!r.ok) return toast(context, r.error!, error: true);
    if (clienteId.isEmpty) return toast(context, 'Selecciona un cliente de la lista (o dalo de alta en Clientes).', error: true);
    if (inp.producto.isEmpty) return toast(context, 'Describe el producto.', error: true);
    if (!r.permitido) return toast(context, 'Cotización no permitida: el margen real es menor al mínimo.', error: true);
    setState(() => saving = true);
    try {
      final id = await Ops.guardarCotizacion(
        id: cotId,
        input: inp.toMap(),
        resultado: r.toMap(),
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        producto: inp.producto,
        cantidad: inp.cantidad,
        total: r.total,
        subtotal: r.subtotal,
        vigenciaDias: params.vigenciaDias,
      );
      await Db.update('cotizaciones', id, {'escalas': escalas, 'requiereHerramental': (inp.costoSuaje + (inp.conImpresion ? inp.costoCliche : 0)) > 0 ? 'true' : 'false'});
      cotId = id;
      final d = await Db.get('cotizaciones', id);
      cotFolio = d?.s('folio');
      if (mounted) {
        setState(() {});
        toast(context, 'Cotización $cotFolio guardada.');
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pdf() async {
    if (cotId == null) await _guardar();
    if (cotId == null) return;
    final cot = await Db.get('cotizaciones', cotId!);
    final emp = await Db.get('config', 'empresa');
    final bytes = await PdfService.cotizacion(cot!, {...kEmpresaDefault, ...?emp?.d});
    await PdfService.imprimir(bytes, 'Cotizacion-${cot.s('folio')}.pdf');
  }

  void _almacen() {
    final r = res!;
    final alts = CotEngine.buscarAlternas(inp, r, params, mps.map((e) => {...e.d, 'sku': e.id}).toList());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Láminas en almacén que coinciden o son similares'),
        content: SizedBox(
          width: 560,
          child: alts.isEmpty
              ? const Text('No hay láminas en almacén con misma flauta/material, ECT suficiente y medidas compatibles.')
              : ListView(shrinkWrap: true, children: [
                  Text('Requerida: ${fmtN(r.laminaLargoM * 100, 1)} x ${fmtN(r.laminaAnchoM * 100, 1)} cm · ${inp.material} · flauta ${inp.flauta} · ECT ≥ ${inp.ect}'),
                  const Divider(),
                  for (final a in alts)
                    ListTile(
                      dense: true,
                      leading: Icon(a.tipo == 'Coincide' ? Icons.check_circle : Icons.compare_arrows, color: a.tipo == 'Coincide' ? Colors.green : Colors.orange),
                      title: Text('${a.sku} · ${fmtN(a.largoCm, 1)} x ${fmtN(a.anchoCm, 1)} cm'),
                      subtitle: Text('${a.descripcion}\n${a.tipo}${a.tipo == 'Similar' ? ' (+${fmtN(a.desperdicioPct, 0)}% área)' : ''} · disponibles ${fmtI(a.disponible)}${a.alcanza ? '' : ' (insuficientes para ${r.laminasReq})'} · ${money(a.costo)}/lámina'),
                      isThreeLine: true,
                      trailing: FilledButton(
                        onPressed: a.costo <= 0
                            ? null
                            : () {
                                Navigator.pop(context);
                                laminaSku = a.sku;
                                precioFijo = a.costo;
                                _recalc();
                              },
                        child: const Text('Usar'),
                      ),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _tf(String k, String label, {String? suffix, String? prefix, bool dec = true, String? helper}) =>
      numField(t(k), label, suffix: suffix, prefix: prefix, dec: dec, onChanged: (_) => _recalc(), helper: helper);

  Widget _form(BuildContext context) {
    final directo = TiposCaja.desarrolloDirecto.contains(tipo);
    return Column(children: [
      SectionCard(title: '1 · Datos del pedido', child: ResponsiveGrid(minItemWidth: 240, children: [
        RecPicker(
          label: 'Cliente',
          items: clientes,
          initial: clienteNombre,
          text: (r) => r.s('nombre'),
          onSelected: (r) {
            clienteId = r.id;
            clienteNombre = r.s('nombre');
            _recalc();
          },
        ),
        textField(t('producto'), 'Producto / descripción', onChanged: (_) => _recalc()),
        RecPicker(
          label: 'Código de producto (opcional)',
          items: productos,
          initial: t('codigo').text,
          text: (r) => '${r.id} · ${r.s('descripcion')}',
          onSelected: (r) {
            t('codigo').text = r.id;
            if (t('producto').text.isEmpty) t('producto').text = r.s('descripcion');
            _recalc();
          },
        ),
        dropdown<String>('Tipo de caja', tipo, TiposCaja.todos, (v) {
          tipo = v!;
          _recalc();
        }),
        _tf('cantidad', 'Cantidad de piezas', dec: false, suffix: 'pzs'),
        _tf('ppl', 'Piezas por lámina', dec: false, helper: 'Si salen varias de una lámina'),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '2 · Medidas y lámina', child: ResponsiveGrid(minItemWidth: 150, children: [
        _tf('largo', 'Largo interno', suffix: 'cm'),
        _tf('ancho', 'Ancho interno', suffix: 'cm'),
        _tf('alto', 'Alto interno', suffix: 'cm'),
        _tf('lamL', directo ? 'Desarrollo: largo lámina *' : 'Largo lámina (directo)', suffix: 'cm', helper: directo ? 'Obligatorio en este tipo' : 'Vacío = calcular'),
        _tf('lamA', directo ? 'Desarrollo: ancho lámina *' : 'Ancho lámina (directo)', suffix: 'cm'),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '3 · Cartón', child: ResponsiveGrid(minItemWidth: 190, children: [
        dropdown<String>('Material (liner)', material, Catalogos.materiales, (v) {
          material = v!;
          _autoPrecio();
          _recalc();
        }),
        dropdown<String>('Flauta', flauta, Catalogos.flautas, (v) {
          flauta = v!;
          _autoPrecio();
          _recalc();
        }, text: (f) => Catalogos.flautaNombre[f]!),
        _tf('ect', 'Resistencia ECT', dec: false, suffix: 'lb/in'),
        _tf('precioM2', 'Precio lámina', prefix: '\$', suffix: '/m²', helper: laminaSku.isEmpty ? 'De la tabla del proveedor; editable' : 'Se usa lámina de almacén $laminaSku'),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '4 · Impresión (cobertura % y precio de tinta)', child: Column(children: [
        for (var k = 0; k < 4; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: _tf('t${k}c', 'Tinta ${k + 1}: % de área', suffix: '%')),
              const SizedBox(width: 8),
              Expanded(child: _tf('t${k}p', 'Precio tinta ${k + 1}', prefix: '\$', suffix: '/kg')),
            ]),
          ),
        Row(children: [
          Expanded(child: _tf('barnizPct', 'Barniz: % de área', suffix: '%')),
          const SizedBox(width: 8),
          Expanded(child: _tf('barnizPrecio', 'Precio barniz', prefix: '\$', suffix: '/kg')),
        ]),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '5 · Acabado, herramentales y empaque', child: Column(children: [
        ResponsiveGrid(minItemWidth: 200, children: [
          dropdown<String>('Acabado', acabado, Catalogos.acabados, (v) {
            acabado = v!;
            _recalc();
          }),
          _tf('cliche', 'Cliché / grabado (solo si hay impresión)', prefix: '\$'),
          _tf('suaje', 'Suaje / troquel', prefix: '\$'),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Prorratear herramentales entre las piezas'), subtitle: const Text('Apagado = se cobran aparte'), value: prorratear, onChanged: (v) {
          prorratear = v;
          _recalc();
        }),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Entarimado'), value: entarimado, onChanged: (v) {
          entarimado = v;
          _recalc();
        }),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '6 · Flete y parte comercial', child: Column(children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('El cliente recoge'), subtitle: const Text('Apagado = se envía (captura el monto del transportista)'), value: recoge, onChanged: (v) {
          recoge = v;
          _recalc();
        }),
        ResponsiveGrid(minItemWidth: 190, children: [
          if (!recoge) _tf('monto', 'Monto del transportista', prefix: '\$'),
          _tf('margen', 'Margen de utilidad', suffix: '%'),
          _tf('descExtra', 'Descuento adicional', suffix: '%'),
          _tf('escalas', 'Otras cantidades (escalas)', dec: false, helper: 'Ej: 500, 2000, 5000'),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Cobrar al cliente el sobrante por mínimo de compra'), value: cobrarSobrante, onChanged: (v) {
          cobrarSobrante = v;
          _recalc();
        }),
        textField(t('notas'), 'Notas / observaciones', lines: 2, onChanged: (_) => _recalc()),
      ])),
    ]);
  }

  Widget _row(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
        ]),
      );

  Widget _resultado(BuildContext context) {
    final r = res;
    if (r == null) return const SizedBox();
    if (!r.ok) return SectionCard(title: 'Resultado', child: Text(r.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      SectionCard(
        title: cotFolio != null ? 'Cotización $cotFolio' : 'Resultado',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PRECIO UNITARIO', style: TextStyle(fontSize: 11, color: cs.outline)),
          Text(money(r.precioUnitConFlete), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: r.permitido ? cs.primary : cs.error)),
          if (r.fletePz > 0) Text('incluye flete ${money(r.fletePz)}/pz', style: TextStyle(color: cs.outline)),
          const Divider(),
          _row('Costo unitario', money(r.costoUnit)),
          _row('Precio recomendado (${params.margenRecomendadoPct.toStringAsFixed(0)}%)', money(r.precioRecomendado)),
          _row('Margen real', '${fmtN(r.margenReal * 100, 1)}%', color: r.permitido ? Colors.green.shade700 : cs.error),
          if (r.descuentoPct > 0) _row('Descuento aplicado', '${fmtN(r.descuentoPct, 1)}%'),
          const Divider(),
          _row('Subtotal', money(r.subtotal)),
          if (r.herramentalAparte > 0) _row('Herramentales (aparte)', money(r.herramentalAparte)),
          _row('IVA ${params.ivaPct.toStringAsFixed(0)}%', money(r.iva)),
          _row('TOTAL', money(r.total), bold: true),
          _row('Total sin IVA', money(r.subtotalConHerr)),
          _row('Utilidad estimada', money(r.utilidadTotal)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: saving ? null : _guardar, icon: const Icon(Icons.save), label: Text(cotId == null ? 'Guardar cotización' : 'Actualizar')),
            OutlinedButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
            if (cotId != null) OutlinedButton.icon(onPressed: () => context.go('/crm'), icon: const Icon(Icons.view_kanban_outlined), label: const Text('Ir al pipeline')),
          ]),
        ]),
      ),
      if (r.advertencias.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          color: cs.errorContainer.withOpacity(.5),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final a in r.advertencias) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.warning_amber, size: 18), const SizedBox(width: 6), Expanded(child: Text(a))])),
              if (!r.cumpleMinimo && laminaSku.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: FilledButton.tonalIcon(onPressed: _almacen, icon: const Icon(Icons.search), label: const Text('Buscar lámina en almacén'))),
            ]),
          ),
        ),
      ],
      if (laminaSku.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.warehouse_outlined),
            title: Text('Usando lámina de almacén: $laminaSku'),
            subtitle: Text('${money(precioFijo)} por lámina · sin mínimo de compra'),
            trailing: TextButton(onPressed: () {
              laminaSku = '';
              precioFijo = 0;
              _recalc();
            }, child: const Text('Quitar')),
          ),
        ),
      ],
      const SizedBox(height: 12),
      SectionCard(title: 'Lámina y metros cuadrados', child: Column(children: [
        _row('Lámina (largo x ancho)', '${fmtN(r.laminaLargoM * 100, 1)} x ${fmtN(r.laminaAnchoM * 100, 1)} cm'),
        _row('Área de la lámina', '${fmtN(r.areaM2, 4)} m²'),
        _row('Piezas por lámina', '${r.piezasPorLamina}'),
        _row('Merma de proceso', '${fmtN(r.mermaPiezas, 0)} pzs (${r.mermaLaminas} láminas)'),
        _row('Láminas requeridas', fmtI(r.laminasReq)),
        _row('m² requeridos', fmtN(r.m2Req, 2)),
        _row('Láminas mínimas proveedor', fmtI(r.laminasMin)),
        _row('m² a comprar', fmtN(r.m2Comprar, 2), bold: true),
        _row('Sobrante', '${fmtN(r.sobranteM2, 2)} m² (${fmtI(r.sobranteLaminas)} láminas)', color: r.sobranteM2 > 0 ? Colors.orange.shade800 : null),
        _row('Precio por lámina', '${money(r.precioLamina)}  (${money(r.precioM2)}/m²)'),
        if (r.pesoCajaKg > 0) _row('Peso aprox. caja / tarima', '${fmtN(r.pesoCajaKg, 3)} kg / ${fmtN(r.pesoTarimaKg, 0)} kg'),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: 'Desglose por pieza', child: Column(children: [
        _row('Material (incl. merma/sobrante)', money(r.material, decimals: true)),
        _row('Tinta', money(r.tinta)),
        _row('Barniz', money(r.barniz)),
        _row('Adhesivo', money(r.adhesivo)),
        _row('Fleje', money(r.fleje)),
        _row('Playo / emplaye', money(r.playo)),
        _row('Tarima', money(r.tarima)),
        _row('Mano de obra', money(r.manoObra)),
        _row('Herramental prorrateado', money(r.herramental)),
        _row('Gastos indirectos', money(r.indirectos)),
        _row('Recargo por volumen', '${fmtN(r.recargoPct, 1)}%'),
        const Divider(),
        _row('Costo unitario', money(r.costoUnit), bold: true),
      ])),
      if (escalas.length > 1) ...[
        const SizedBox(height: 12),
        SectionCard(title: 'Escalas de volumen', child: Table(columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(.8)}, children: [
          const TableRow(children: [Text('Cantidad', style: TextStyle(fontWeight: FontWeight.bold)), Text('Precio unit.', style: TextStyle(fontWeight: FontWeight.bold)), Text('Subtotal', style: TextStyle(fontWeight: FontWeight.bold)), Text('Margen', style: TextStyle(fontWeight: FontWeight.bold))]),
          for (final e in escalas)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(fmtI(e['cantidad'] as num))),
              Text(money(e['precioUnitConFlete'] as num)),
              Text(money(e['total'] as num, decimals: false)),
              Text('${fmtN((e['margen'] as num) * 100, 0)}%', style: TextStyle(color: e['permitido'] == true ? null : Colors.red)),
            ]),
        ])),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return PageBody(
      title: cotFolio != null ? 'Editar cotización $cotFolio' : 'Cotizador',
      subtitle: 'Cálculo de lámina, m², costos y precio con los parámetros reales de Cartón Boom',
      actions: [
        if (cotId != null) OutlinedButton.icon(onPressed: () => context.go('/cotizador'), icon: const Icon(Icons.add), label: const Text('Nueva')),
      ],
      child: isWide(context)
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: _form(context)),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _resultado(context)),
            ])
          : Column(children: [_resultado(context), const SizedBox(height: 12), _form(context)]),
    );
  }
}
