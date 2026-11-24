import '../../core/constants.dart';

double _d(dynamic v, double def) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? def);
Map<String, double> _mapD(dynamic v, Map<String, double> def) {
  if (v is! Map) return Map.of(def);
  return {for (final e in def.entries) e.key: _d(v[e.key], e.value)};
}

class TramoDescuento {
  final double desde, pct;
  const TramoDescuento(this.desde, this.pct);
}

class TramoMerma {
  final double hasta, piezas;
  const TramoMerma(this.hasta, this.piezas);
}

/// Parámetros del cotizador. Se guardan en Firestore: parametros/cotizador.
/// Valores por defecto tomados de "Base de Datos Cotizador" del Excel.
class CotParams {
  // Comercial
  double minimoCompraM2 = 400; // Word: mínimo del proveedor
  double ivaPct = 16;
  double margenMinimoPct = 15; // Excel: < 15% => cotización no permitida
  double margenRecomendadoPct = 30; // Excel: precio recomendado = costo / (1 - 30%)
  double margenDefaultPct = 30;
  int vigenciaDias = 30;
  String condicionesPago = '50% de anticipo y 50% contra entrega. Precios sujetos a cambio sin previo aviso; no incluyen IVA.';
  List<TramoDescuento> descuentosVolumen = [const TramoDescuento(1000, 3), const TramoDescuento(5000, 5)];
  double toleranciaRecepcionPct = 10; // ±10% proveedor

  // Desarrollo de lámina (metros) por flauta - Excel V7/W7/AD7/AE7
  Map<String, double> tolLargo = {'C': 0.051, 'B': 0.048, 'BC': 0.075, 'E': 0.041};
  Map<String, double> tolAncho = {'C': 0.01, 'B': 0.01, 'BC': 0.024, 'E': 0.005};
  double pestanaPegue = 0.015;
  Map<String, double> tolCharolaLargo = {'C': 0.012, 'B': 0.011, 'BC': 0.016, 'E': 0.010};
  Map<String, double> tolCharolaAncho = {'C': 0.062, 'B': 0.06, 'BC': 0.084, 'E': 0.053};
  double extraSuaje = 0.03; // suajado: desarrollo + 3 cm

  // Empaque / consumibles
  Map<String, double> calibre = {'C': 0.004, 'B': 0.003, 'BC': 0.008, 'E': 0.002};
  Map<String, double> piezasPaquete = {'C': 25, 'B': 25, 'BC': 15, 'E': 50};
  Map<String, double> piezasTarima = {'C': 1000, 'B': 1000, 'BC': 600, 'E': 2500};
  double precioFlejeKg = 25.97;
  double precioTarima = 107;
  double precioAdhesivoKg = 144.74;
  double precioPlayoKg = 115;
  double rendTintaKgM2 = 0.02931769722814499;
  double rendAdhesivoKgM = 0.013605442176870748;
  double flejeKgPorM = 0.0013;
  double playoKgPorTarima = 0.86;

  // Merma de proceso (piezas) por tramo de pedido - Excel W54:W57
  List<TramoMerma> mermaTramos = [const TramoMerma(5000, 150), const TramoMerma(50000, 300)];
  double mermaMayor = 300;

  // Recargo por volumen - Excel W49/W51
  double recargoPequenoA = 2, recargoPequenoB = 0.0015, umbralPequeno = 500;
  double recargoGrandeA = 0.05, recargoGrandeB = 0.000001;

  // Indirectos: total / producción de referencia - Excel I23
  double indirectosTotal = 314337.48;
  double produccionBase = 3986090;

  // Mano de obra por operación ($/día) y capacidad ($ -> pz/día)
  Map<String, double> costoDiaOperacion = {
    'operacional': 4283.3333,
    'flexo': 441.6667,
    'suajado': 441.6667,
    'pegadora': 1108.3333,
    'rayadora': 441.6667,
    'acabado': 1108.3333,
  };
  double capacidadDiaria = 35000;
  double costoPreparacionPedido = 0;
  Map<String, List<String>> procesos = {
    TiposCaja.crr: ['operacional', 'flexo', 'pegadora', 'acabado'],
    TiposCaja.suajado: ['operacional', 'suajado', 'acabado'],
    TiposCaja.charola: ['operacional', 'suajado', 'acabado'],
    TiposCaja.mediasCajas: ['operacional', 'flexo', 'pegadora', 'acabado'],
    TiposCaja.traslapada: ['operacional', 'flexo', 'pegadora', 'acabado'],
    TiposCaja.charolaAuto: ['operacional', 'suajado', 'pegadora', 'acabado'],
    TiposCaja.sinTapas: ['operacional', 'flexo', 'pegadora', 'acabado'],
    TiposCaja.separador: ['operacional', 'suajado', 'acabado'],
  };

  // Límites de máquina (m) - Excel "Tolerancias Boom/Maquila"
  double maxLargoBoom = 2.0, maxAnchoBoom = 1.4, minLargoBoom = 0.52, minAnchoBoom = 0.26;
  double minLargoCorrugadora = 0.75, maxAnchoMaquila = 1.2;

  // Búsqueda en almacén cuando no se cumple el mínimo
  double toleranciaAlmacenCm = 1.0; // "coincide"
  double holguraAlmacenPct = 15; // "similar": hasta 15% más grande en área

  CotParams();

  factory CotParams.fromMap(Map<String, dynamic>? m) {
    final p = CotParams();
    if (m == null) return p;
    p.minimoCompraM2 = _d(m['minimoCompraM2'], p.minimoCompraM2);
    p.ivaPct = _d(m['ivaPct'], p.ivaPct);
    p.margenMinimoPct = _d(m['margenMinimoPct'], p.margenMinimoPct);
    p.margenRecomendadoPct = _d(m['margenRecomendadoPct'], p.margenRecomendadoPct);
    p.margenDefaultPct = _d(m['margenDefaultPct'], p.margenDefaultPct);
    p.vigenciaDias = _d(m['vigenciaDias'], p.vigenciaDias.toDouble()).round();
    p.condicionesPago = (m['condicionesPago'] ?? p.condicionesPago).toString();
    p.toleranciaRecepcionPct = _d(m['toleranciaRecepcionPct'], p.toleranciaRecepcionPct);
    if (m['descuentosVolumen'] is List) {
      p.descuentosVolumen = [
        for (final t in m['descuentosVolumen'] as List) TramoDescuento(_d((t as Map)['desde'], 0), _d(t['pct'], 0))
      ]..sort((a, b) => a.desde.compareTo(b.desde));
    }
    p.tolLargo = _mapD(m['tolLargo'], p.tolLargo);
    p.tolAncho = _mapD(m['tolAncho'], p.tolAncho);
    p.pestanaPegue = _d(m['pestanaPegue'], p.pestanaPegue);
    p.tolCharolaLargo = _mapD(m['tolCharolaLargo'], p.tolCharolaLargo);
    p.tolCharolaAncho = _mapD(m['tolCharolaAncho'], p.tolCharolaAncho);
    p.extraSuaje = _d(m['extraSuaje'], p.extraSuaje);
    p.calibre = _mapD(m['calibre'], p.calibre);
    p.piezasPaquete = _mapD(m['piezasPaquete'], p.piezasPaquete);
    p.piezasTarima = _mapD(m['piezasTarima'], p.piezasTarima);
    p.precioFlejeKg = _d(m['precioFlejeKg'], p.precioFlejeKg);
    p.precioTarima = _d(m['precioTarima'], p.precioTarima);
    p.precioAdhesivoKg = _d(m['precioAdhesivoKg'], p.precioAdhesivoKg);
    p.precioPlayoKg = _d(m['precioPlayoKg'], p.precioPlayoKg);
    p.rendTintaKgM2 = _d(m['rendTintaKgM2'], p.rendTintaKgM2);
    p.rendAdhesivoKgM = _d(m['rendAdhesivoKgM'], p.rendAdhesivoKgM);
    p.flejeKgPorM = _d(m['flejeKgPorM'], p.flejeKgPorM);
    p.playoKgPorTarima = _d(m['playoKgPorTarima'], p.playoKgPorTarima);
    if (m['mermaTramos'] is List) {
      p.mermaTramos = [for (final t in m['mermaTramos'] as List) TramoMerma(_d((t as Map)['hasta'], 0), _d(t['piezas'], 0))]
        ..sort((a, b) => a.hasta.compareTo(b.hasta));
    }
    p.mermaMayor = _d(m['mermaMayor'], p.mermaMayor);
    p.recargoPequenoA = _d(m['recargoPequenoA'], p.recargoPequenoA);
    p.recargoPequenoB = _d(m['recargoPequenoB'], p.recargoPequenoB);
    p.umbralPequeno = _d(m['umbralPequeno'], p.umbralPequeno);
    p.recargoGrandeA = _d(m['recargoGrandeA'], p.recargoGrandeA);
    p.recargoGrandeB = _d(m['recargoGrandeB'], p.recargoGrandeB);
    p.indirectosTotal = _d(m['indirectosTotal'], p.indirectosTotal);
    p.produccionBase = _d(m['produccionBase'], p.produccionBase);
    p.costoDiaOperacion = _mapD(m['costoDiaOperacion'], p.costoDiaOperacion);
    p.capacidadDiaria = _d(m['capacidadDiaria'], p.capacidadDiaria);
    p.costoPreparacionPedido = _d(m['costoPreparacionPedido'], p.costoPreparacionPedido);
    if (m['procesos'] is Map) {
      final pr = m['procesos'] as Map;
      for (final k in p.procesos.keys.toList()) {
        if (pr[k] is List) p.procesos[k] = [for (final x in pr[k] as List) x.toString()];
      }
    }
    p.maxLargoBoom = _d(m['maxLargoBoom'], p.maxLargoBoom);
    p.maxAnchoBoom = _d(m['maxAnchoBoom'], p.maxAnchoBoom);
    p.minLargoBoom = _d(m['minLargoBoom'], p.minLargoBoom);
    p.minAnchoBoom = _d(m['minAnchoBoom'], p.minAnchoBoom);
    p.minLargoCorrugadora = _d(m['minLargoCorrugadora'], p.minLargoCorrugadora);
    p.maxAnchoMaquila = _d(m['maxAnchoMaquila'], p.maxAnchoMaquila);
    p.toleranciaAlmacenCm = _d(m['toleranciaAlmacenCm'], p.toleranciaAlmacenCm);
    p.holguraAlmacenPct = _d(m['holguraAlmacenPct'], p.holguraAlmacenPct);
    return p;
  }

  Map<String, dynamic> toMap() => {
        'minimoCompraM2': minimoCompraM2,
        'ivaPct': ivaPct,
        'margenMinimoPct': margenMinimoPct,
        'margenRecomendadoPct': margenRecomendadoPct,
        'margenDefaultPct': margenDefaultPct,
        'vigenciaDias': vigenciaDias,
        'condicionesPago': condicionesPago,
        'toleranciaRecepcionPct': toleranciaRecepcionPct,
        'descuentosVolumen': [for (final t in descuentosVolumen) {'desde': t.desde, 'pct': t.pct}],
        'tolLargo': tolLargo,
        'tolAncho': tolAncho,
        'pestanaPegue': pestanaPegue,
        'tolCharolaLargo': tolCharolaLargo,
        'tolCharolaAncho': tolCharolaAncho,
        'extraSuaje': extraSuaje,
        'calibre': calibre,
        'piezasPaquete': piezasPaquete,
        'piezasTarima': piezasTarima,
        'precioFlejeKg': precioFlejeKg,
        'precioTarima': precioTarima,
        'precioAdhesivoKg': precioAdhesivoKg,
        'precioPlayoKg': precioPlayoKg,
        'rendTintaKgM2': rendTintaKgM2,
        'rendAdhesivoKgM': rendAdhesivoKgM,
        'flejeKgPorM': flejeKgPorM,
        'playoKgPorTarima': playoKgPorTarima,
        'mermaTramos': [for (final t in mermaTramos) {'hasta': t.hasta, 'piezas': t.piezas}],
        'mermaMayor': mermaMayor,
        'recargoPequenoA': recargoPequenoA,
        'recargoPequenoB': recargoPequenoB,
        'umbralPequeno': umbralPequeno,
        'recargoGrandeA': recargoGrandeA,
        'recargoGrandeB': recargoGrandeB,
        'indirectosTotal': indirectosTotal,
        'produccionBase': produccionBase,
        'costoDiaOperacion': costoDiaOperacion,
        'capacidadDiaria': capacidadDiaria,
        'costoPreparacionPedido': costoPreparacionPedido,
        'procesos': procesos,
        'maxLargoBoom': maxLargoBoom,
        'maxAnchoBoom': maxAnchoBoom,
        'minLargoBoom': minLargoBoom,
        'minAnchoBoom': minAnchoBoom,
        'minLargoCorrugadora': minLargoCorrugadora,
        'maxAnchoMaquila': maxAnchoMaquila,
        'toleranciaAlmacenCm': toleranciaAlmacenCm,
        'holguraAlmacenPct': holguraAlmacenPct,
      };
}
