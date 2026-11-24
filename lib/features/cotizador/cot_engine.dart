import 'dart:math';

import '../../core/constants.dart';
import 'cot_params.dart';

double _r2(double v) => (v * 100).roundToDouble() / 100;
double _dd(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

class TintaIn {
  double cobertura; // % del área impresa
  double precioKg;
  TintaIn(this.cobertura, this.precioKg);
  Map<String, dynamic> toMap() => {'cobertura': cobertura, 'precioKg': precioKg};
  factory TintaIn.fromMap(Map m) => TintaIn(_dd(m['cobertura']), _dd(m['precioKg']));
}

/// Datos que captura quien cotiza.
class CotInput {
  String clienteId = '', clienteNombre = '', producto = '', codigoProducto = '';
  String tipo = TiposCaja.crr;
  double largo = 0, ancho = 0, alto = 0; // medidas internas (cm)
  int cantidad = 0;
  String material = 'Kraft', flauta = 'C';
  int ect = 23;
  double? laminaLargoCm, laminaAnchoCm; // desarrollo directo
  int piezasPorLamina = 1;
  List<TintaIn> tintas = [];
  double barnizPct = 0, barnizPrecioKg = 0;
  String acabado = 'Pegada';
  bool entarimado = true;
  double costoCliche = 0, costoSuaje = 0;
  bool prorratearHerramental = true;
  double precioM2 = 0; // $/m² de la lámina (tabla del proveedor o manual)
  double precioLaminaFijo = 0; // $/lámina (lámina de almacén)
  String laminaAlmacenSku = '';
  bool cobrarSobrante = true;
  bool clienteRecoge = true;
  double montoTransportista = 0;
  double margenPct = 30;
  double descuentoExtraPct = 0;
  String notas = '';

  CotInput();

  CotInput copy() => CotInput.fromMap(toMap());

  Map<String, dynamic> toMap() => {
        'clienteId': clienteId,
        'clienteNombre': clienteNombre,
        'producto': producto,
        'codigoProducto': codigoProducto,
        'tipo': tipo,
        'largo': largo,
        'ancho': ancho,
        'alto': alto,
        'cantidad': cantidad,
        'material': material,
        'flauta': flauta,
        'ect': ect,
        'laminaLargoCm': laminaLargoCm,
        'laminaAnchoCm': laminaAnchoCm,
        'piezasPorLamina': piezasPorLamina,
        'tintas': [for (final t in tintas) t.toMap()],
        'barnizPct': barnizPct,
        'barnizPrecioKg': barnizPrecioKg,
        'acabado': acabado,
        'entarimado': entarimado,
        'costoCliche': costoCliche,
        'costoSuaje': costoSuaje,
        'prorratearHerramental': prorratearHerramental,
        'precioM2': precioM2,
        'precioLaminaFijo': precioLaminaFijo,
        'laminaAlmacenSku': laminaAlmacenSku,
        'cobrarSobrante': cobrarSobrante,
        'clienteRecoge': clienteRecoge,
        'montoTransportista': montoTransportista,
        'margenPct': margenPct,
        'descuentoExtraPct': descuentoExtraPct,
        'notas': notas,
      };

  factory CotInput.fromMap(Map<String, dynamic> m) {
    final i = CotInput();
    i.clienteId = '${m['clienteId'] ?? ''}';
    i.clienteNombre = '${m['clienteNombre'] ?? ''}';
    i.producto = '${m['producto'] ?? ''}';
    i.codigoProducto = '${m['codigoProducto'] ?? ''}';
    i.tipo = '${m['tipo'] ?? TiposCaja.crr}';
    i.largo = _dd(m['largo']);
    i.ancho = _dd(m['ancho']);
    i.alto = _dd(m['alto']);
    i.cantidad = _dd(m['cantidad']).round();
    i.material = '${m['material'] ?? 'Kraft'}';
    i.flauta = '${m['flauta'] ?? 'C'}';
    i.ect = _dd(m['ect']).round();
    i.laminaLargoCm = m['laminaLargoCm'] == null ? null : _dd(m['laminaLargoCm']);
    i.laminaAnchoCm = m['laminaAnchoCm'] == null ? null : _dd(m['laminaAnchoCm']);
    i.piezasPorLamina = max(1, _dd(m['piezasPorLamina']).round());
    i.tintas = m['tintas'] is List ? [for (final t in m['tintas'] as List) TintaIn.fromMap(t as Map)] : [];
    i.barnizPct = _dd(m['barnizPct']);
    i.barnizPrecioKg = _dd(m['barnizPrecioKg']);
    i.acabado = '${m['acabado'] ?? 'Pegada'}';
    i.entarimado = m['entarimado'] != false;
    i.costoCliche = _dd(m['costoCliche']);
    i.costoSuaje = _dd(m['costoSuaje']);
    i.prorratearHerramental = m['prorratearHerramental'] != false;
    i.precioM2 = _dd(m['precioM2']);
    i.precioLaminaFijo = _dd(m['precioLaminaFijo']);
    i.laminaAlmacenSku = '${m['laminaAlmacenSku'] ?? ''}';
    i.cobrarSobrante = m['cobrarSobrante'] != false;
    i.clienteRecoge = m['clienteRecoge'] != false;
    i.montoTransportista = _dd(m['montoTransportista']);
    i.margenPct = m['margenPct'] == null ? 30 : _dd(m['margenPct']);
    i.descuentoExtraPct = _dd(m['descuentoExtraPct']);
    i.notas = '${m['notas'] ?? ''}';
    return i;
  }

  int get numTintas => tintas.where((t) => t.cobertura > 0).length;
  bool get conImpresion => numTintas > 0;
}

class LaminaAlterna {
  final String sku, descripcion, tipo; // tipo: Coincide | Similar
  final double largoCm, anchoCm, disponible, costo, desperdicioPct;
  final bool alcanza;
  LaminaAlterna(this.sku, this.descripcion, this.tipo, this.largoCm, this.anchoCm, this.disponible, this.costo, this.desperdicioPct, this.alcanza);
}

class CotResult {
  String? error;
  bool get ok => error == null;

  // Lámina y m²
  double laminaLargoM = 0, laminaAnchoM = 0, areaM2 = 0;
  int piezasPorLamina = 1, laminasReq = 0, mermaLaminas = 0, laminasMin = 0, laminasComprar = 0, sobranteLaminas = 0;
  double mermaPiezas = 0, m2Req = 0, m2Comprar = 0, sobranteM2 = 0;
  bool cumpleMinimo = true;

  // Materia prima
  double precioM2 = 0, precioLamina = 0, costoMaterialTotal = 0;

  // Costos por pieza
  double material = 0, tinta = 0, barniz = 0, adhesivo = 0, fleje = 0, playo = 0, tarima = 0, manoObra = 0, herramental = 0;
  double directo = 0, indirectos = 0, costoFab = 0, recargoPct = 0, costoUnit = 0;

  // Comercial
  double precioRecomendado = 0, precioBase = 0, descuentoPct = 0, precioUnit = 0, margenReal = 0;
  bool permitido = true;
  double fletePz = 0, precioUnitConFlete = 0, subtotal = 0, herramentalAparte = 0, subtotalConHerr = 0, iva = 0, total = 0;

  // Utilidad ($)
  double utilidadTotal = 0;

  // Peso
  double pesoCajaKg = 0, pesoTarimaKg = 0;

  List<String> advertencias = [];

  Map<String, dynamic> toMap() => {
        'laminaLargoCm': laminaLargoM * 100,
        'laminaAnchoCm': laminaAnchoM * 100,
        'areaM2': areaM2,
        'laminasReq': laminasReq,
        'm2Req': m2Req,
        'm2Comprar': m2Comprar,
        'sobranteM2': sobranteM2,
        'cumpleMinimo': cumpleMinimo,
        'precioLamina': precioLamina,
        'material': material,
        'tinta': tinta,
        'barniz': barniz,
        'adhesivo': adhesivo,
        'fleje': fleje,
        'playo': playo,
        'tarima': tarima,
        'manoObra': manoObra,
        'herramental': herramental,
        'indirectos': indirectos,
        'recargoPct': recargoPct,
        'costoUnit': costoUnit,
        'precioUnit': precioUnit,
        'descuentoPct': descuentoPct,
        'margenReal': margenReal,
        'fletePz': fletePz,
        'precioUnitConFlete': precioUnitConFlete,
        'subtotal': subtotal,
        'herramentalAparte': herramentalAparte,
        'iva': iva,
        'total': total,
        'utilidadTotal': utilidadTotal,
        'pesoCajaKg': pesoCajaKg,
      };
}

class CotEngine {
  static const _tolSolapa = {'C': 0.002, 'B': 0.002, 'BC': 0.004, 'E': 0.001};
  static const _tolTraslapada = {'C': 0.02, 'B': 0.02, 'BC': 0.038, 'E': 0.01};

  /// Peso (g por 10x10 cm) según ECT y material. [tabla] = filas de catalogo_ect.
  static double? pesoG10x10(List<Map<String, dynamic>> tabla, String flauta, String material, int ect) {
    final tipo = flauta == 'BC' ? 'doble' : (flauta == 'E' ? 'micro' : 'sencillo');
    Map<String, dynamic>? mejor;
    for (final r in tabla) {
      if ('${r['tipo']}' != tipo || '${r['material']}'.toLowerCase() != material.toLowerCase()) continue;
      final e = _dd(r['ect']);
      if (e <= ect && (mejor == null || e > _dd(mejor['ect']))) mejor = r;
    }
    return mejor == null ? null : _dd(mejor['pesoG10x10']);
  }

  static CotResult calcular(CotInput i, CotParams p, {double? pesoG10x10}) {
    final r = CotResult();
    final q = i.cantidad;
    if (q <= 0) return r..error = 'Captura la cantidad de piezas.';
    final f = i.flauta;
    final directo = TiposCaja.desarrolloDirecto.contains(i.tipo);
    final hayOverride = (i.laminaLargoCm ?? 0) > 0 && (i.laminaAnchoCm ?? 0) > 0;

    // ---------- Desarrollo de lámina ----------
    double largoM, anchoM;
    if (directo || hayOverride) {
      if (!hayOverride) return r..error = 'Este tipo de caja requiere capturar el desarrollo (largo y ancho de lámina, en cm).';
      largoM = i.laminaLargoCm! / 100;
      anchoM = i.laminaAnchoCm! / 100;
      if (i.tipo == TiposCaja.suajado) {
        largoM += p.extraSuaje;
        anchoM += p.extraSuaje;
      }
    } else {
      if (i.largo <= 0 || i.ancho <= 0 || i.alto <= 0) return r..error = 'Captura largo, ancho y alto de la caja.';
      final l = i.largo / 100, a = i.ancho / 100, h = i.alto / 100;
      final tl = p.tolLargo[f] ?? 0, ta = p.tolAncho[f] ?? 0;
      switch (i.tipo) {
        case TiposCaja.charola:
          largoM = (l + 2 * h) + (p.tolCharolaLargo[f] ?? 0);
          anchoM = (a + h) + (p.tolCharolaAncho[f] ?? 0);
          break;
        case TiposCaja.sinTapas:
          largoM = (l + a) * 2 + tl + p.pestanaPegue;
          anchoM = (a / 2 + h) + ta;
          break;
        case TiposCaja.traslapada:
          largoM = (l + a) * 2 + tl + p.pestanaPegue;
          anchoM = (2 * a + h) + (_tolTraslapada[f] ?? 0);
          break;
        default: // CRR y medias cajas
          largoM = (l + a) * 2 + tl + p.pestanaPegue;
          anchoM = (a + h) + ta;
      }
    }
    r.laminaLargoM = largoM;
    r.laminaAnchoM = anchoM;
    r.areaM2 = largoM * anchoM;
    if (r.areaM2 <= 0) return r..error = 'El área de la lámina es cero; revisa las medidas.';
    final ppl = max(1, i.piezasPorLamina);
    r.piezasPorLamina = ppl;

    // ---------- Láminas, m², mínimo del proveedor ----------
    r.mermaPiezas = p.mermaMayor;
    for (final t in p.mermaTramos) {
      if (q <= t.hasta) {
        r.mermaPiezas = t.piezas;
        break;
      }
    }
    r.mermaLaminas = (r.mermaPiezas / ppl).ceil();
    r.laminasReq = (q / ppl).ceil() + r.mermaLaminas;
    r.m2Req = r.areaM2 * r.laminasReq;
    final deAlmacen = i.laminaAlmacenSku.isNotEmpty;
    r.laminasMin = deAlmacen ? 0 : (p.minimoCompraM2 / r.areaM2 - 1e-9).ceil();
    r.cumpleMinimo = deAlmacen || r.m2Req >= p.minimoCompraM2;
    final m2Compra = deAlmacen ? r.m2Req : max(r.m2Req, p.minimoCompraM2);
    r.laminasComprar = max(r.laminasReq, (m2Compra / r.areaM2 - 1e-9).ceil());
    r.m2Comprar = r.laminasComprar * r.areaM2;
    r.sobranteLaminas = r.laminasComprar - r.laminasReq;
    r.sobranteM2 = r.m2Comprar - r.m2Req;

    // ---------- Materia prima ----------
    if (i.precioLaminaFijo > 0) {
      r.precioLamina = i.precioLaminaFijo;
      r.precioM2 = r.precioLamina / r.areaM2;
    } else if (i.precioM2 > 0) {
      r.precioM2 = i.precioM2;
      r.precioLamina = i.precioM2 * r.areaM2;
    } else {
      return r..error = 'Falta el precio de la lámina (\$/m² o \$/lámina). Selecciónalo de la tabla o captúralo.';
    }
    r.costoMaterialTotal = (i.cobrarSobrante ? r.laminasComprar : r.laminasReq) * r.precioLamina;
    r.material = r.costoMaterialTotal / q;

    // ---------- Proceso (por pieza) ----------
    for (final t in i.tintas) {
      if (t.cobertura > 0) r.tinta += r.areaM2 * (t.cobertura / 100) * t.precioKg * p.rendTintaKgM2 / ppl;
    }
    if (i.barnizPct > 0) r.barniz = r.areaM2 * (i.barnizPct / 100) * i.barnizPrecioKg * p.rendTintaKgM2 / ppl;

    if (TiposCaja.conAdhesivo.contains(i.tipo) && i.acabado == 'Pegada') {
      final ts = _tolSolapa[f] ?? 0;
      final solapa = (i.ancho / 200) + ts;
      final panel = max(0.0, anchoM - 2 * solapa);
      r.adhesivo = p.rendAdhesivoKgM * panel * p.precioAdhesivoKg;
    }
    final pzPaq = p.piezasPaquete[f] ?? 25;
    final pzTar = p.piezasTarima[f] ?? 1000;
    final cal = p.calibre[f] ?? 0.004;
    final flejeM = (((cal * 3) * pzPaq * 2) + ((i.alto / 100) * 2) + 0.03) * 2;
    r.fleje = (flejeM / pzPaq) * p.flejeKgPorM * p.precioFlejeKg;
    r.playo = (p.playoKgPorTarima / pzTar) * p.precioPlayoKg;
    r.tarima = i.entarimado ? p.precioTarima / pzTar : 0;

    var dia = 0.0;
    for (final op in p.procesos[i.tipo] ?? const <String>[]) {
      if (op == 'pegadora' && i.acabado != 'Pegada') continue;
      dia += p.costoDiaOperacion[op] ?? 0;
    }
    r.manoObra = dia / max(1, p.capacidadDiaria) + p.costoPreparacionPedido / q;

    final cliche = i.conImpresion ? i.costoCliche : 0.0;
    final herr = cliche + i.costoSuaje;
    if (i.prorratearHerramental) {
      r.herramental = herr / q;
    } else {
      r.herramentalAparte = herr;
    }

    r.directo = r.material + r.tinta + r.barniz + r.adhesivo + r.fleje + r.playo + r.tarima + r.manoObra + r.herramental;
    r.indirectos = p.produccionBase > 0 ? p.indirectosTotal / p.produccionBase : 0;
    r.costoFab = r.directo + r.indirectos;

    // Recargo por volumen (Excel: factor para volumen)
    final rec = q < p.umbralPequeno ? (p.recargoPequenoA - p.recargoPequenoB * (q - 1)) : (p.recargoGrandeA - p.recargoGrandeB * (q - 1));
    r.recargoPct = max(0, rec) * 100;
    r.costoUnit = r.costoFab * (1 + max(0, rec));

    // ---------- Parte comercial ----------
    final mg = i.margenPct.clamp(0, 95).toDouble();
    r.precioRecomendado = r.costoUnit / (1 - p.margenRecomendadoPct / 100);
    r.precioBase = r.costoUnit / (1 - mg / 100);
    var desc = 0.0;
    for (final t in p.descuentosVolumen) {
      if (q >= t.desde) desc = t.pct;
    }
    r.descuentoPct = desc + i.descuentoExtraPct;
    r.precioUnit = _r2(r.precioBase * (1 - r.descuentoPct / 100));
    r.margenReal = r.precioUnit > 0 ? (1 - r.costoUnit / r.precioUnit) : 0;
    r.permitido = r.margenReal * 100 >= p.margenMinimoPct;
    r.fletePz = i.clienteRecoge ? 0 : _r2(i.montoTransportista / q);
    r.precioUnitConFlete = _r2(r.precioUnit + r.fletePz);
    r.subtotal = _r2(r.precioUnitConFlete * q);
    r.subtotalConHerr = r.subtotal + r.herramentalAparte;
    r.iva = _r2(r.subtotalConHerr * p.ivaPct / 100);
    r.total = r.subtotalConHerr + r.iva;
    r.utilidadTotal = (r.precioUnit - r.costoUnit) * q + r.herramentalAparte;

    if (pesoG10x10 != null) {
      r.pesoCajaKg = (pesoG10x10 / 10) * r.areaM2;
      r.pesoTarimaKg = r.pesoCajaKg * pzTar;
    }

    // ---------- Advertencias ----------
    if (!r.permitido) r.advertencias.add('COTIZACIÓN NO PERMITIDA: margen real ${(r.margenReal * 100).toStringAsFixed(1)}% < mínimo ${p.margenMinimoPct}%.');
    if (!r.cumpleMinimo) r.advertencias.add('No se alcanza el mínimo de compra (${p.minimoCompraM2.toStringAsFixed(0)} m²). Se compran ${r.m2Comprar.toStringAsFixed(1)} m² y sobran ${r.sobranteM2.toStringAsFixed(1)} m². Revisa láminas en almacén.');
    if (largoM > p.maxLargoBoom) r.advertencias.add('Lámina muy larga (${largoM.toStringAsFixed(2)} m > ${p.maxLargoBoom} m): medias cajas o maquila.');
    if (anchoM > p.maxAnchoBoom) r.advertencias.add('Lámina muy ancha (${anchoM.toStringAsFixed(2)} m > ${p.maxAnchoBoom} m): maquila.');
    if (largoM < p.minLargoBoom) r.advertencias.add('Lámina muy corta (${largoM.toStringAsFixed(2)} m < ${p.minLargoBoom} m): considerar múltiplos.');
    if (anchoM < p.minAnchoBoom) r.advertencias.add('Lámina muy angosta (${anchoM.toStringAsFixed(2)} m < ${p.minAnchoBoom} m): considerar múltiplos.');
    if (largoM < p.minLargoCorrugadora) r.advertencias.add('Largo menor al mínimo de corrugadora (${p.minLargoCorrugadora} m): requiere múltiplos.');
    if (anchoM > p.maxAnchoMaquila && i.conImpresion) r.advertencias.add('Ancho > ${p.maxAnchoMaquila} m con impresión: valorar caja suajada / maquila.');
    if (i.tipo == TiposCaja.suajado && i.costoSuaje <= 0) r.advertencias.add('Caja suajada sin costo de suaje capturado.');
    if (i.conImpresion && i.costoCliche <= 0) r.advertencias.add('Lleva impresión pero no se capturó costo de cliché.');
    return r;
  }

  /// Busca láminas en almacén parecidas a la requerida (cuando no se cumple el mínimo de compra).
  static List<LaminaAlterna> buscarAlternas(CotInput i, CotResult r, CotParams p, List<Map<String, dynamic>> mps) {
    final lc = r.laminaLargoM * 100, ac = r.laminaAnchoM * 100;
    final tol = p.toleranciaAlmacenCm;
    final out = <LaminaAlterna>[];
    for (final m in mps) {
      final stock = _dd(m['stock']) - _dd(m['reservado']);
      if (stock <= 0) continue;
      if ('${m['material']}'.toLowerCase() != i.material.toLowerCase()) continue;
      if ('${m['flauta']}' != i.flauta) continue;
      final ect = _dd(m['ect']);
      if (ect > 0 && ect < i.ect) continue;
      final lm = _dd(m['largoMm']) / 10, am = _dd(m['anchoMm']) / 10;
      if (lm <= 0 || am <= 0) continue;
      for (final o in [[lm, am], [am, lm]]) {
        final a = o[0], b = o[1];
        String? tipo;
        if ((a - lc).abs() <= tol && (b - ac).abs() <= tol) {
          tipo = 'Coincide';
        } else if (a >= lc - tol && b >= ac - tol && ((a * b) / (lc * ac) - 1) * 100 <= p.holguraAlmacenPct) {
          tipo = 'Similar';
        }
        if (tipo != null) {
          out.add(LaminaAlterna('${m['sku']}', '${m['descripcion']}', tipo, a, b, stock, _dd(m['costoUnitario']),
              ((a * b) / (lc * ac) - 1) * 100, stock >= r.laminasReq));
          break;
        }
      }
    }
    out.sort((x, y) {
      if (x.tipo != y.tipo) return x.tipo == 'Coincide' ? -1 : 1;
      return x.desperdicioPct.compareTo(y.desperdicioPct);
    });
    return out;
  }
}
