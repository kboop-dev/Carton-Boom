import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../core/db.dart';
import '../core/session.dart';
import '../core/utils.dart';

/// Operaciones de negocio transaccionales (consistencia garantizada por Firestore).
class Ops {
  static FirebaseFirestore get fs => Db.fs;
  static String get _quien => Session.I.nombre;

  static double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  /// Folio consecutivo por año: PREFIJO-AAAA-0001. Debe llamarse ANTES de cualquier escritura de la transacción.
  static Future<String> _folio(Transaction tx, String clave, String prefijo) async {
    final y = DateTime.now().year;
    final ref = fs.collection('contadores').doc('$clave-$y');
    final s = await tx.get(ref);
    final n = (s.exists ? _n(s.data()!['valor']).toInt() : 0) + 1;
    tx.set(ref, {'valor': n});
    return '$prefijo-$y-${n.toString().padLeft(4, '0')}';
  }

  static Future<String> siguienteFolioCotizacion() => fs.runTransaction((tx) => _folio(tx, 'COT', 'COT'));

  static void _evento(Transaction tx, String ordenId, int cp, String estado, [Map<String, dynamic>? datos]) {
    tx.set(fs.collection('ordenes').doc(ordenId).collection('eventos').doc(), {
      'checkpoint': cp,
      'estado': estado,
      'uid': Db.uid,
      'usuario': _quien,
      'ts': FieldValue.serverTimestamp(),
      'datos': datos ?? {},
    });
  }

  // ------------------------------------------------------------------ CRM
  static Future<String> guardarCotizacion({
    String? id,
    required Map<String, dynamic> input,
    required Map<String, dynamic> resultado,
    required String clienteId,
    required String clienteNombre,
    required String producto,
    required int cantidad,
    required double total,
    required double subtotal,
    required int vigenciaDias,
  }) async {
    if (id == null) {
      final folio = await siguienteFolioCotizacion();
      return Db.add('cotizaciones', {
        'folio': folio,
        'estado': EstadoCot.pendiente,
        'clienteId': clienteId,
        'clienteNombre': clienteNombre,
        'producto': producto,
        'cantidad': cantidad,
        'input': input,
        'resultado': resultado,
        'subtotal': subtotal,
        'total': total,
        'vigenciaDias': vigenciaDias,
        'fecha': FieldValue.serverTimestamp(),
        'vendedor': _quien,
      });
    }
    await Db.update('cotizaciones', id, {
      'clienteId': clienteId,
      'clienteNombre': clienteNombre,
      'producto': producto,
      'cantidad': cantidad,
      'input': input,
      'resultado': resultado,
      'subtotal': subtotal,
      'total': total,
      'vigenciaDias': vigenciaDias,
    });
    return id;
  }

  /// Aprobar cotización => genera la Orden Viajera (Hoja de Ruta) con folio y QR.
  static Future<String> aprobarCotizacion(String cotId, {DateTime? fechaCompromiso}) async {
    final out = await fs.runTransaction<String>((tx) async {
      final cref = fs.collection('cotizaciones').doc(cotId);
      final cs = await tx.get(cref);
      if (!cs.exists) throw Exception('La cotización no existe.');
      final c = cs.data()!;
      if (c['estado'] != EstadoCot.pendiente) throw Exception('La cotización ya no está pendiente (${c['estado']}).');
      final folio = await _folio(tx, 'OT', 'OT');
      final oref = fs.collection('ordenes').doc();
      final input = Map<String, dynamic>.from(c['input'] as Map? ?? {});
      final res = Map<String, dynamic>.from(c['resultado'] as Map? ?? {});
      final tintas = (input['tintas'] as List?)?.where((t) => _n((t as Map)['cobertura']) > 0).length ?? 0;
      tx.set(oref, Db.stamp({
        'folio': folio,
        'cotizacionId': cotId,
        'cotizacionFolio': c['folio'],
        'clienteId': c['clienteId'],
        'clienteNombre': c['clienteNombre'],
        'producto': c['producto'],
        'productoSku': input['codigoProducto'] ?? '',
        'cantidad': c['cantidad'],
        'specs': {
          'tipoCaja': input['tipo'],
          'largo': input['largo'],
          'ancho': input['ancho'],
          'alto': input['alto'],
          'material': input['material'],
          'flauta': input['flauta'],
          'ect': input['ect'],
          'tintas': tintas,
          'acabado': input['acabado'],
          'laminaLargoCm': res['laminaLargoCm'],
          'laminaAnchoCm': res['laminaAnchoCm'],
          'laminasReq': res['laminasReq'],
          'entarimado': input['entarimado'],
          'clienteRecoge': input['clienteRecoge'],
          'notas': input['notas'],
        },
        'laminaSku': input['laminaAlmacenSku'] ?? '',
        'estado': EstadoOt.pendienteMp,
        'checkpoint': 0,
        'laminasAsignadas': 0,
        'laminasConsumidas': 0,
        'aprobadas': 0,
        'mermas': 0,
        'total': c['total'],
        'qr': 'CBOT|${oref.id}',
        'fechaAprobacion': FieldValue.serverTimestamp(),
        if (fechaCompromiso != null) 'fechaCompromiso': Timestamp.fromDate(fechaCompromiso),
      }, create: true));
      tx.update(cref, {
        'estado': EstadoCot.aprobada,
        'ordenId': oref.id,
        'ordenFolio': folio,
        'fechaAprobacion': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if ('${c['clienteId']}'.isNotEmpty) {
        tx.set(
            fs.collection('clientes').doc('${c['clienteId']}'),
            {'ultimoPedido': FieldValue.serverTimestamp(), 'totalPedidos': FieldValue.increment(1), 'estado': 'activo', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
      }
      _evento(tx, oref.id, 0, EstadoOt.pendienteMp, {'accion': 'Orden generada al aprobar ${c['folio']}'});
      tx.set(fs.collection('tareas').doc(), Db.stamp({
        'titulo': 'Despachar materia prima de $folio',
        'detalle': '${c['clienteNombre']} · ${c['producto']} · ${c['cantidad']} pzs',
        'estado': 'pendiente',
        'prioridad': 'alta',
        'fecha': Timestamp.fromDate(DateTime.now()),
        'origen': 'auto',
        'origenClave': 'ot:${oref.id}:mp',
        'ruta': '/planta?ot=${oref.id}',
      }, create: true));
      return oref.id;
    });
    return out;
  }

  static Future<void> cambiarEstadoCotizacion(String id, String estado, {String? motivo}) =>
      Db.update('cotizaciones', id, {'estado': estado, if (motivo != null) 'motivo': motivo});

  // -------------------------------------------------------- Planta (checkpoints)
  static Future<void> cp1AsignarMp({required String ordenId, required String sku, required double laminas}) async {
    if (laminas <= 0) throw Exception('Indica cuántas láminas se entregan.');
    await fs.runTransaction((tx) async {
      final oref = fs.collection('ordenes').doc(ordenId);
      final mref = fs.collection('materias_primas').doc(sku);
      final o = await tx.get(oref);
      final m = await tx.get(mref);
      if (!o.exists) throw Exception('Orden no encontrada.');
      if (!m.exists) throw Exception('La materia prima $sku no existe en inventario.');
      final od = o.data()!;
      if (EstadoOt.flujo.indexOf('${od['estado']}') > EstadoOt.flujo.indexOf(EstadoOt.mpAsignada) && _n(od['laminasConsumidas']) > 0) {
        throw Exception('La orden ya consumió material; usa "Láminas de ajuste".');
      }
      final md = m.data()!;
      final disponible = _n(md['stock']) - _n(md['reservado']);
      final yaAsignadas = '${od['laminaSku']}' == sku ? _n(od['laminasAsignadas']) : 0.0;
      if (disponible + yaAsignadas < laminas) {
        throw Exception('Existencia insuficiente de $sku: disponible ${fmtN(disponible + yaAsignadas, 0)}, solicitado ${fmtN(laminas, 0)}.');
      }
      // Si ya había una asignación previa de otro SKU, libera su reserva.
      final prevSku = '${od['laminaSku']}';
      if (prevSku.isNotEmpty && prevSku != sku && _n(od['laminasAsignadas']) > 0) {
        final prev = await tx.get(fs.collection('materias_primas').doc(prevSku));
        if (prev.exists) {
          tx.update(prev.reference, {'reservado': (_n(prev.data()!['reservado']) - _n(od['laminasAsignadas'])).clamp(0, 1e12)});
        }
      }
      tx.update(mref, {'reservado': _n(md['reservado']) + laminas - yaAsignadas, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
      tx.update(oref, {
        'laminaSku': sku,
        'laminasAsignadas': laminas,
        'estado': EstadoOt.mpAsignada,
        'checkpoint': 1,
        'fechaMp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _evento(tx, ordenId, 1, EstadoOt.mpAsignada, {'sku': sku, 'laminas': laminas});
      if ('${od['cotizacionId']}'.isNotEmpty) {
        tx.update(fs.collection('cotizaciones').doc('${od['cotizacionId']}'), {'estado': EstadoCot.produccion, 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }

  static Future<void> _simple(String ordenId, String estado, int cp, {Map<String, dynamic>? extra}) async {
    await fs.runTransaction((tx) async {
      final oref = fs.collection('ordenes').doc(ordenId);
      final o = await tx.get(oref);
      if (!o.exists) throw Exception('Orden no encontrada.');
      tx.update(oref, {'estado': estado, 'checkpoint': cp, 'updatedAt': FieldValue.serverTimestamp(), ...?extra});
      _evento(tx, ordenId, cp, estado);
    });
  }

  /// CP2: no bloquea el sistema si la máquina se detiene; se mantiene en este estado.
  static Future<void> cp2Impresion(String ordenId) => _simple(ordenId, EstadoOt.impresion, 2, extra: {'fechaImpresion': FieldValue.serverTimestamp()});

  /// CP3: Cajas aprobadas + mermas. Descuenta láminas del inventario y registra merma.
  /// Devuelve true si aún faltan piezas (aprobadas < solicitadas).
  static Future<bool> cp3Calidad({required String ordenId, required int aprobadas, required int mermas, String? causa, String? tipoMerma}) async {
    if (aprobadas < 0 || mermas < 0) throw Exception('Los valores no pueden ser negativos.');
    return fs.runTransaction<bool>((tx) async {
      final oref = fs.collection('ordenes').doc(ordenId);
      final o = await tx.get(oref);
      if (!o.exists) throw Exception('Orden no encontrada.');
      final od = o.data()!;
      final sku = '${od['laminaSku'] ?? ''}';
      DocumentSnapshot<Map<String, dynamic>>? m;
      if (sku.isNotEmpty) m = await tx.get(fs.collection('materias_primas').doc(sku));

      final asignadas = _n(od['laminasAsignadas']);
      final consumidas = _n(od['laminasConsumidas']);
      final consumo = (asignadas - consumidas).clamp(0, 1e12).toDouble();
      final totalAprob = _n(od['aprobadas']) + aprobadas;
      final totalMerma = _n(od['mermas']) + mermas;
      final cantidad = _n(od['cantidad']);

      double costoMerma = 0;
      if (m != null && m.exists) {
        final md = m.data()!;
        costoMerma = mermas * _n(md['costoUnitario']);
        tx.update(m.reference, {
          'stock': _n(md['stock']) - consumo,
          'reservado': (_n(md['reservado']) - consumo).clamp(0, 1e12),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': Db.uid,
        });
        if (consumo > 0) {
          tx.set(fs.collection('movimientos_mp').doc(), Db.stamp({
            'tipo': 'salida_produccion',
            'sku': sku,
            'cantidad': consumo,
            'ordenId': ordenId,
            'folio': od['folio'],
            'fecha': FieldValue.serverTimestamp(),
            'usuario': _quien,
          }, create: true));
        }
      }
      final specs = Map<String, dynamic>.from(od['specs'] as Map? ?? {});
      if (mermas > 0) {
        tx.set(fs.collection('mermas').doc(), Db.stamp({
          'fecha': FieldValue.serverTimestamp(),
          'ordenId': ordenId,
          'folio': od['folio'],
          'sku': sku,
          'cantidad': mermas,
          'costo': costoMerma,
          'tipo': tipoMerma ?? 'Producción',
          'causa': causa ?? '',
          'tipoTrabajo': specs['tipoCaja'] ?? '',
          'tintas': specs['tintas'] ?? 0,
          'clienteNombre': od['clienteNombre'],
        }, create: true));
      }
      final falta = totalAprob < cantidad;
      tx.update(oref, {
        'aprobadas': totalAprob,
        'mermas': totalMerma,
        'laminasConsumidas': consumidas + consumo,
        'estado': EstadoOt.calidad,
        'checkpoint': 3,
        'requiereAjuste': falta,
        'faltante': falta ? cantidad - totalAprob : 0,
        'fechaCalidad': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _evento(tx, ordenId, 3, EstadoOt.calidad, {'aprobadas': aprobadas, 'mermas': mermas, 'consumo': consumo});
      return falta;
    });
  }

  static Future<String> solicitarAjuste({required String ordenId, required String folio, required String sku, required double laminas, required String cliente}) async {
    final id = await Db.add('solicitudes_ajuste', {
      'ordenId': ordenId,
      'folio': folio,
      'sku': sku,
      'laminas': laminas,
      'cliente': cliente,
      'estado': 'Pendiente',
      'solicitante': _quien,
    });
    await Db.add('tareas', {
      'titulo': 'Entregar $laminas láminas de ajuste · $folio',
      'detalle': '$cliente · SKU $sku',
      'estado': 'pendiente',
      'prioridad': 'alta',
      'fecha': Timestamp.fromDate(DateTime.now()),
      'origen': 'auto',
      'origenClave': 'ajuste:$id',
      'ruta': '/planta?ot=$ordenId',
    });
    return id;
  }

  /// Almacén entrega láminas de ajuste: suma a asignadas y reserva.
  static Future<void> atenderAjuste(String solId) async {
    await fs.runTransaction((tx) async {
      final sref = fs.collection('solicitudes_ajuste').doc(solId);
      final s = await tx.get(sref);
      if (!s.exists) throw Exception('Solicitud no encontrada.');
      final sd = s.data()!;
      if (sd['estado'] != 'Pendiente') throw Exception('La solicitud ya fue atendida.');
      final oref = fs.collection('ordenes').doc('${sd['ordenId']}');
      final mref = fs.collection('materias_primas').doc('${sd['sku']}');
      final o = await tx.get(oref);
      final m = await tx.get(mref);
      final n = _n(sd['laminas']);
      final md = m.data()!;
      if (_n(md['stock']) - _n(md['reservado']) < n) throw Exception('Existencia insuficiente para el ajuste.');
      tx.update(mref, {'reservado': _n(md['reservado']) + n, 'updatedAt': FieldValue.serverTimestamp()});
      tx.update(oref, {'laminasAsignadas': _n(o.data()!['laminasAsignadas']) + n, 'estado': EstadoOt.impresion, 'checkpoint': 2, 'requiereAjuste': false, 'updatedAt': FieldValue.serverTimestamp()});
      tx.update(sref, {'estado': 'Atendida', 'atendio': _quien, 'fechaAtendida': FieldValue.serverTimestamp()});
      _evento(tx, '${sd['ordenId']}', 2, EstadoOt.impresion, {'ajuste': n});
    });
  }

  static Future<void> cp4Armado(String ordenId) => _simple(ordenId, EstadoOt.armado, 4, extra: {'fechaArmado': FieldValue.serverTimestamp()});
  static Future<void> cp4Finalizar(String ordenId) => _simple(ordenId, EstadoOt.finalizado, 4, extra: {'fechaFinalizado': FieldValue.serverTimestamp()});

  /// CP5: producto terminado listo. Opcionalmente ingresa al inventario PT.
  static Future<void> cp5Listo({required String ordenId, String? productoSku, String? lote}) async {
    await fs.runTransaction((tx) async {
      final oref = fs.collection('ordenes').doc(ordenId);
      final o = await tx.get(oref);
      if (!o.exists) throw Exception('Orden no encontrada.');
      final od = o.data()!;
      DocumentSnapshot<Map<String, dynamic>>? p;
      if (productoSku != null && productoSku.isNotEmpty) p = await tx.get(fs.collection('productos').doc(productoSku));
      if (p != null && p.exists && od['ptIngresado'] != true) {
        final cant = _n(od['aprobadas']);
        tx.update(p.reference, {'stock': _n(p.data()!['stock']) + cant, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
        tx.set(fs.collection('movimientos_pt').doc(), Db.stamp({
          'tipo': 'entrada_produccion',
          'sku': productoSku,
          'cantidad': cant,
          'lote': lote ?? '${od['folio']}',
          'ordenId': ordenId,
          'folio': od['folio'],
          'fecha': FieldValue.serverTimestamp(),
          'usuario': _quien,
        }, create: true));
      }
      tx.update(oref, {
        'estado': EstadoOt.listo,
        'checkpoint': 5,
        'productoSku': productoSku ?? '',
        'ptIngresado': p != null && p.exists ? true : (od['ptIngresado'] ?? false),
        'fechaListo': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _evento(tx, ordenId, 5, EstadoOt.listo);
    });
  }

  /// Entrega al cliente (flete o recolección). Cierra orden y cotización.
  static Future<void> entregar({required String ordenId, String? factura, int? satisfaccion, String? transportista}) async {
    await fs.runTransaction((tx) async {
      final oref = fs.collection('ordenes').doc(ordenId);
      final o = await tx.get(oref);
      if (!o.exists) throw Exception('Orden no encontrada.');
      final od = o.data()!;
      final sku = '${od['productoSku'] ?? ''}';
      DocumentSnapshot<Map<String, dynamic>>? p;
      if (sku.isNotEmpty && od['ptIngresado'] == true) p = await tx.get(fs.collection('productos').doc(sku));
      if (p != null && p.exists) {
        final cant = _n(od['aprobadas']);
        tx.update(p.reference, {'stock': _n(p.data()!['stock']) - cant, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
        tx.set(fs.collection('movimientos_pt').doc(), Db.stamp({
          'tipo': 'salida_entrega',
          'sku': sku,
          'cantidad': cant,
          'factura': factura ?? '',
          'ordenId': ordenId,
          'folio': od['folio'],
          'fecha': FieldValue.serverTimestamp(),
          'usuario': _quien,
        }, create: true));
      }
      tx.update(oref, {
        'estado': EstadoOt.entregada,
        'checkpoint': 5,
        'factura': factura ?? '',
        'transportista': transportista ?? '',
        if (satisfaccion != null) 'satisfaccion': satisfaccion,
        'fechaEntregada': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if ('${od['cotizacionId']}'.isNotEmpty) {
        tx.update(fs.collection('cotizaciones').doc('${od['cotizacionId']}'), {'estado': EstadoCot.entregada, 'fechaEntrega': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
      }
      _evento(tx, ordenId, 5, EstadoOt.entregada, {'factura': factura ?? '', 'satisfaccion': satisfaccion});
    });
  }

  // ------------------------------------------------------------ Inventarios
  /// Entrada de materia prima (escaneo de código de barras). Valida ±tolerancia contra lo pedido.
  static Future<Map<String, dynamic>> entradaMp({
    required String sku,
    required double cantidad,
    required double toleranciaPct,
    String? lote,
    String? documento,
    String? proveedorId,
    String? proveedorNombre,
    double? costoUnitario,
    double? cantidadPedida,
  }) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a cero.');
    final res = await fs.runTransaction<Map<String, dynamic>>((tx) async {
      final mref = fs.collection('materias_primas').doc(sku);
      final m = await tx.get(mref);
      if (!m.exists) throw Exception('El SKU $sku no existe. Da de alta la materia prima primero.');
      final md = m.data()!;
      final stock = _n(md['stock']);
      final nuevo = stock + cantidad;
      var costo = _n(md['costoUnitario']);
      if (costoUnitario != null && costoUnitario > 0) {
        final base = stock > 0 ? stock : 0.0;
        costo = (base * costo + cantidad * costoUnitario) / (base + cantidad);
      }
      double? desv;
      bool? dentro;
      if (cantidadPedida != null && cantidadPedida > 0) {
        desv = (cantidad - cantidadPedida) / cantidadPedida * 100;
        dentro = desv.abs() <= toleranciaPct;
      }
      tx.update(mref, {'stock': nuevo, 'costoUnitario': costo, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
      tx.set(fs.collection('movimientos_mp').doc(), Db.stamp({
        'tipo': 'entrada',
        'sku': sku,
        'descripcion': md['descripcion'],
        'cantidad': cantidad,
        'lote': lote ?? '',
        'documento': documento ?? '',
        'proveedorId': proveedorId ?? '',
        'proveedor': proveedorNombre ?? '',
        'costoUnitario': costoUnitario ?? 0,
        'cantidadPedida': cantidadPedida ?? 0,
        'desviacionPct': desv,
        'dentroTolerancia': dentro,
        'fecha': FieldValue.serverTimestamp(),
        'usuario': _quien,
      }, create: true));
      return {'stock': nuevo, 'desviacionPct': desv, 'dentroTolerancia': dentro, 'descripcion': md['descripcion']};
    });
    return res;
  }

  static Future<void> ajusteMp({required String sku, required double stockReal, required String motivo}) async {
    await fs.runTransaction((tx) async {
      final mref = fs.collection('materias_primas').doc(sku);
      final m = await tx.get(mref);
      if (!m.exists) throw Exception('SKU inexistente.');
      final actual = _n(m.data()!['stock']);
      tx.update(mref, {'stock': stockReal, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
      tx.set(fs.collection('movimientos_mp').doc(), Db.stamp({
        'tipo': 'ajuste',
        'sku': sku,
        'cantidad': stockReal - actual,
        'motivo': motivo,
        'fecha': FieldValue.serverTimestamp(),
        'usuario': _quien,
      }, create: true));
    });
  }

  static Future<void> movimientoPt({required String sku, required double cantidad, required bool entrada, String? lote, String? factura, String? ordenCompra}) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a cero.');
    await fs.runTransaction((tx) async {
      final pref = fs.collection('productos').doc(sku);
      final p = await tx.get(pref);
      if (!p.exists) throw Exception('El producto $sku no existe.');
      final stock = _n(p.data()!['stock']);
      if (!entrada && stock < cantidad) throw Exception('Existencia insuficiente (hay ${fmtN(stock, 0)}).');
      tx.update(pref, {'stock': entrada ? stock + cantidad : stock - cantidad, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': Db.uid});
      tx.set(fs.collection('movimientos_pt').doc(), Db.stamp({
        'tipo': entrada ? 'entrada' : 'salida',
        'sku': sku,
        'cantidad': cantidad,
        'lote': lote ?? '',
        'factura': factura ?? '',
        'ordenCompra': ordenCompra ?? '',
        'fecha': FieldValue.serverTimestamp(),
        'usuario': _quien,
      }, create: true));
    });
  }

  /// Crea/actualiza una tarea automática por stock bajo mínimo (sin duplicarla).
  static Future<void> revisarStockBajo(String sku) async {
    final m = await Db.get('materias_primas', sku);
    if (m == null) return;
    final minimo = m.n('minimo');
    if (minimo <= 0 || m.n('stock') > minimo) return;
    final clave = 'stock:$sku';
    final existentes = await fs.collection('tareas').where('origenClave', isEqualTo: clave).get();
    if (existentes.docs.any((d) => d.data()['estado'] != 'hecha')) return;
    await Db.add('tareas', {
      'titulo': 'Reabastecer $sku',
      'detalle': '${m.s('descripcion')} · stock ${fmtN(m.n('stock'), 0)} ≤ mínimo ${fmtN(minimo, 0)}',
      'estado': 'pendiente',
      'prioridad': 'alta',
      'fecha': Timestamp.fromDate(DateTime.now()),
      'origen': 'auto',
      'origenClave': clave,
      'ruta': '/inventario',
    });
  }
}
