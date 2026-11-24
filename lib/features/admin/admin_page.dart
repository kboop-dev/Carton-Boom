import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../services/pdf_service.dart';
import '../cotizador/cot_params.dart';

/// Carga inicial de catálogos desde assets/seed/seed.json (extraído de tu Excel PRP y cotizador).
/// Es SEGURA de repetir: solo crea lo que falta; nunca modifica documentos que ya existen
/// (no toca existencias, costos, parámetros editados ni datos de empresa).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool busy = false, conStock = false;
  String log = '';

  void _l(String s) => setState(() => log += '$s\n');

  Future<void> _commit(List<void Function(WriteBatch)> ops) async {
    for (var i = 0; i < ops.length; i += 400) {
      final b = Db.fs.batch();
      for (final o in ops.skip(i).take(400)) {
        o(b);
      }
      await b.commit();
    }
  }

  Future<Set<String>> _ids(String c) async =>
      (await Db.getAll(c)).map((e) => e.id).toSet();

  Future<void> cargar() async {
    setState(() {
      busy = true;
      log = '';
    });
    try {
      final seed =
          jsonDecode(await rootBundle.loadString('assets/seed/seed.json'))
              as Map<String, dynamic>;
      final ts = FieldValue.serverTimestamp();
      Map<String, dynamic> base(Map<String, dynamic> m) =>
          {...m, 'createdAt': ts, 'updatedAt': ts, 'createdBy': Db.uid};

      final exParam = await _ids('parametros');
      final exCfg = await _ids('config');
      final exMp = await _ids('materias_primas');
      final exPt = await _ids('productos');
      final exBom = await _ids('bom');
      final exProv = await _ids('proveedores');
      final exEct = await _ids('catalogo_ect');
      final exPre = await _ids('precios_carton');

      final ops = <void Function(WriteBatch)>[];
      var nuevos = 0, existentes = 0;
      void crear(String col, String id, Set<String> existe,
          Map<String, dynamic> data) {
        if (existe.contains(id)) {
          existentes++;
          return;
        }
        nuevos++;
        ops.add((b) => b.set(Db.col(col).doc(id), base(data)));
      }

      crear('parametros', 'cotizador', exParam, CotParams().toMap());
      crear('config', 'empresa', exCfg,
          Map<String, dynamic>.from(kEmpresaDefault));

      for (final m in (seed['materiasPrimas'] as List)) {
        final mp = Map<String, dynamic>.from(m as Map);
        final sku = mp['sku'] as String;
        final stockExcel = (mp.remove('stockExcel') as num?)?.toDouble() ?? 0;
        final area =
            ((mp['largoMm'] ?? 0) as num) * ((mp['anchoMm'] ?? 0) as num) / 1e6;
        final costo = (mp['costoUnitario'] as num?)?.toDouble() ?? 0;
        crear('materias_primas', sku, exMp, {
          ...mp,
          'stock': conStock ? stockExcel : 0,
          'reservado': 0,
          'precioM2': area > 0 ? costo / area : 0,
          'barcode': sku,
          'activo': true,
        });
      }

      for (final p in (seed['productos'] as List)) {
        final pr = Map<String, dynamic>.from(p as Map);
        final sku =
            (pr['sku'] as String).replaceAll('*', '-').replaceAll('/', '-');
        final st = (pr.remove('stockExcel') as num?)?.toDouble() ?? 0;
        crear('productos', sku, exPt,
            {...pr, 'sku': sku, 'stock': conStock ? st : 0, 'barcode': sku});
      }

      for (final x in (seed['bom'] as List)) {
        final m = Map<String, dynamic>.from(x as Map);
        crear('bom', '${m['skuPt']}__${m['skuMp']}'.replaceAll('/', '-'), exBom,
            m);
      }

      for (final x in (seed['proveedores'] as List)) {
        final m = Map<String, dynamic>.from(x as Map);
        crear('proveedores', '${m['codigo']}', exProv, m);
      }

      final ect = seed['ectPesos'] as List;
      for (final e in ect) {
        final m = Map<String, dynamic>.from(e as Map);
        crear('catalogo_ect', '${m['tipo']}_${m['material']}_${m['ect']}',
            exEct, m);
      }

      // Precios de lámina por m² (promedio derivado de tus costos por lámina; CONFIRMAR con proveedor).
      final grupos = <String, List<double>>{};
      for (final m in (seed['materiasPrimas'] as List)) {
        final mp = m as Map;
        final area =
            ((mp['largoMm'] ?? 0) as num) * ((mp['anchoMm'] ?? 0) as num) / 1e6;
        final costo = (mp['costoUnitario'] as num?)?.toDouble() ?? 0;
        if (area > 0 && costo > 0)
          grupos
              .putIfAbsent('${mp['material']}|${mp['flauta']}', () => [])
              .add(costo / area);
      }
      grupos.forEach((k, v) {
        final partes = k.split('|');
        final prom = v.reduce((a, b) => a + b) / v.length;
        crear('precios_carton', '${partes[0]}_${partes[1]}'.toLowerCase(),
            exPre, {
          'material': partes[0],
          'flauta': partes[1],
          'precioM2': double.parse(prom.toStringAsFixed(2)),
          'nota': 'Derivado del PRP; confirmar con proveedor',
        });
      });

      await _commit(ops);
      _l('Documentos creados: $nuevos');
      _l('Ya existían (no se tocaron): $existentes');
      _l('LISTO ✔ Carga completada.');
    } catch (e) {
      _l('ERROR: ${errMsg(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Administración',
      subtitle: 'Carga inicial de datos del sistema',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionCard(
          title: 'Cargar catálogos desde tus Excel (PRP + Cotizador)',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Crea los documentos que falten: parámetros del cotizador, datos de empresa, materias primas (código de barras = SKU), productos terminados, BOM, proveedores, pesos por ECT y precios de cartón por m². Es seguro repetirlo: lo que ya existe NO se modifica (existencias, costos y parámetros editados se conservan).'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: conStock,
              onChanged: (v) => setState(() => conStock = v),
              title: const Text(
                  'Importar también existencias del Excel como inventario inicial'),
              subtitle: const Text(
                  'Solo aplica a SKUs nuevos. Déjalo apagado si esos datos eran de prueba.'),
            ),
            FilledButton.icon(
                onPressed: busy ? null : cargar,
                icon: const Icon(Icons.cloud_upload),
                label: Text(busy ? 'Cargando...' : 'Cargar datos iniciales')),
            if (log.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(log)),
          ]),
        ),
      ]),
    );
  }
}
