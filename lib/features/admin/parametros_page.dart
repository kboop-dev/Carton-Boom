import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../cotizador/cot_params.dart';

/// Edita parámetros del cotizador y datos de empresa sin tocar código (se aplican al instante en todos los equipos).
class ParametrosPage extends StatefulWidget {
  const ParametrosPage({super.key});
  @override
  State<ParametrosPage> createState() => _ParametrosPageState();
}

class _ParametrosPageState extends State<ParametrosPage> {
  CotParams? p;
  final ctl = <String, TextEditingController>{};
  bool loaded = false;

  TextEditingController c(String k, double v) => ctl.putIfAbsent(k, () => TextEditingController(text: _fmt(v)));
  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    Db.get('parametros', 'cotizador').then((r) {
      setState(() {
        p = CotParams.fromMap(r?.d);
        loaded = true;
      });
    });
  }

  double v(String k) => toD(ctl[k]?.text);

  Future<void> guardar() async {
    final x = p!;
    x.minimoCompraM2 = v('minimoCompraM2');
    x.ivaPct = v('ivaPct');
    x.margenMinimoPct = v('margenMinimoPct');
    x.margenRecomendadoPct = v('margenRecomendadoPct');
    x.margenDefaultPct = v('margenDefaultPct');
    x.vigenciaDias = v('vigenciaDias').round();
    x.toleranciaRecepcionPct = v('toleranciaRecepcionPct');
    x.condicionesPago = ctl['condicionesPago']!.text;
    x.precioFlejeKg = v('precioFlejeKg');
    x.precioTarima = v('precioTarima');
    x.precioAdhesivoKg = v('precioAdhesivoKg');
    x.precioPlayoKg = v('precioPlayoKg');
    x.rendTintaKgM2 = v('rendTintaKgM2');
    x.rendAdhesivoKgM = v('rendAdhesivoKgM');
    x.indirectosTotal = v('indirectosTotal');
    x.produccionBase = v('produccionBase');
    x.capacidadDiaria = v('capacidadDiaria');
    x.costoPreparacionPedido = v('costoPreparacionPedido');
    x.maxLargoBoom = v('maxLargoBoom');
    x.maxAnchoBoom = v('maxAnchoBoom');
    x.minLargoBoom = v('minLargoBoom');
    x.minAnchoBoom = v('minAnchoBoom');
    x.minLargoCorrugadora = v('minLargoCorrugadora');
    x.toleranciaAlmacenCm = v('toleranciaAlmacenCm');
    x.holguraAlmacenPct = v('holguraAlmacenPct');
    for (final k in x.costoDiaOperacion.keys.toList()) {
      x.costoDiaOperacion[k] = v('op_$k');
    }
    x.descuentosVolumen = [
      for (var i = 0; i < 3; i++)
        if (v('desc_desde$i') > 0) TramoDescuento(v('desc_desde$i'), v('desc_pct$i')),
    ]..sort((a, b) => a.desde.compareTo(b.desde));
    try {
      await Db.set('parametros', 'cotizador', x.toMap());
      if (mounted) toast(context, 'Parámetros guardados. Se aplican de inmediato a todos los usuarios.');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Widget sec(String t, List<Widget> kids) => SectionCard(title: t, child: ResponsiveGrid(minItemWidth: 200, children: kids));

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final x = p!;
    final tramos = x.descuentosVolumen;
    return PageBody(
      title: 'Parámetros del cotizador',
      subtitle: 'Costos, mermas, límites de máquina y reglas comerciales (editable por supervisor / admin)',
      actions: [FilledButton.icon(onPressed: guardar, icon: const Icon(Icons.save), label: const Text('Guardar'))],
      child: Column(children: [
        sec('Comercial', [
          numField(c('minimoCompraM2', x.minimoCompraM2), 'Mínimo de compra proveedor', suffix: 'm²'),
          numField(c('margenDefaultPct', x.margenDefaultPct), 'Margen por defecto', suffix: '%'),
          numField(c('margenRecomendadoPct', x.margenRecomendadoPct), 'Margen recomendado', suffix: '%'),
          numField(c('margenMinimoPct', x.margenMinimoPct), 'Margen mínimo permitido', suffix: '%'),
          numField(c('ivaPct', x.ivaPct), 'IVA', suffix: '%'),
          numField(c('vigenciaDias', x.vigenciaDias.toDouble()), 'Vigencia cotización', suffix: 'días', dec: false),
          numField(c('toleranciaRecepcionPct', x.toleranciaRecepcionPct), 'Tolerancia de recepción (±)', suffix: '%'),
          for (var i = 0; i < 3; i++) ...[
            numField(c('desc_desde$i', i < tramos.length ? tramos[i].desde : 0), 'Descuento volumen ${i + 1}: desde', suffix: 'pzs'),
            numField(c('desc_pct$i', i < tramos.length ? tramos[i].pct : 0), 'Descuento volumen ${i + 1}: %', suffix: '%'),
          ],
        ]),
        const SizedBox(height: 12),
        SectionCard(title: 'Condiciones de pago (texto en cotización)', child: textField(ctl.putIfAbsent('condicionesPago', () => TextEditingController(text: x.condicionesPago)), 'Condiciones', lines: 2)),
        const SizedBox(height: 12),
        sec('Consumibles y rendimientos', [
          numField(c('precioFlejeKg', x.precioFlejeKg), 'Fleje mosca', prefix: '\$', suffix: '/kg'),
          numField(c('precioTarima', x.precioTarima), 'Tarima tacón', prefix: '\$', suffix: '/pza'),
          numField(c('precioAdhesivoKg', x.precioAdhesivoKg), 'Adhesivo', prefix: '\$', suffix: '/kg'),
          numField(c('precioPlayoKg', x.precioPlayoKg), 'Playo (emplaye)', prefix: '\$', suffix: '/kg'),
          numField(c('rendTintaKgM2', x.rendTintaKgM2), 'Rendimiento de tinta', suffix: 'kg/m²'),
          numField(c('rendAdhesivoKgM', x.rendAdhesivoKgM), 'Rendimiento adhesivo', suffix: 'kg/m'),
        ]),
        const SizedBox(height: 12),
        sec('Mano de obra e indirectos', [
          for (final e in x.costoDiaOperacion.entries) numField(c('op_${e.key}', e.value), 'Costo diario · ${e.key}', prefix: '\$'),
          numField(c('capacidadDiaria', x.capacidadDiaria), 'Capacidad diaria', suffix: 'pzs/día'),
          numField(c('costoPreparacionPedido', x.costoPreparacionPedido), 'Preparación por pedido', prefix: '\$'),
          numField(c('indirectosTotal', x.indirectosTotal), 'Indirectos (total)', prefix: '\$'),
          numField(c('produccionBase', x.produccionBase), 'Producción de referencia', suffix: 'pzs'),
        ]),
        const SizedBox(height: 12),
        sec('Límites de máquina y búsqueda en almacén (m / cm)', [
          numField(c('maxLargoBoom', x.maxLargoBoom), 'Largo máx. Boom', suffix: 'm'),
          numField(c('maxAnchoBoom', x.maxAnchoBoom), 'Ancho máx. Boom', suffix: 'm'),
          numField(c('minLargoBoom', x.minLargoBoom), 'Largo mín. Boom', suffix: 'm'),
          numField(c('minAnchoBoom', x.minAnchoBoom), 'Ancho mín. Boom', suffix: 'm'),
          numField(c('minLargoCorrugadora', x.minLargoCorrugadora), 'Largo mín. corrugadora', suffix: 'm'),
          numField(c('toleranciaAlmacenCm', x.toleranciaAlmacenCm), 'Tolerancia "coincide"', suffix: 'cm'),
          numField(c('holguraAlmacenPct', x.holguraAlmacenPct), 'Holgura "similar"', suffix: '%'),
        ]),
        const SizedBox(height: 12),
        Text('Las tablas de desarrollo por flauta, merma por tramo y recargo por volumen viven en Firestore (parametros/cotizador) con los valores del Excel original.', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
      ]),
    );
  }
}
