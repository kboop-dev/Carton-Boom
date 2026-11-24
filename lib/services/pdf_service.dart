import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/db.dart';
import '../core/utils.dart';

/// Datos de la empresa (editables en Firestore: config/empresa). Valores de la hoja "Cotización Simple".
const kEmpresaDefault = <String, dynamic>{
  'nombre': 'Carton Boom S.A. de C.V.',
  'direccion': 'Vicente Suárez No. 43\nColonia: Revolución mexicana\nSan Pedro Huaquilpan, Zapotlán,\nHidalgo, México',
  'contacto': 'Oficina: 993 189 6830\ncartonboom.mx@gmail.com',
  'datosBancarios': '',
  'leyendas':
      '*Los precios están sujetos a las cantidades mencionadas.\n*Los precios están sujetos a cambio sin previo aviso; no incluyen el IVA.\n*Se entrega a pie de camión, el servicio no incluye maniobras.\n*El tiempo de entrega es de 20 días hábiles, una vez confirmada la compra.\n*Para iniciar la fabricación se deberá haber entregado: maestra de producción firmada, OC emitida correctamente y el anticipo.\n*Pedidos ingresados después de las 12 pm se capturan el día hábil siguiente.\n*Una vez iniciado el proceso de fabricación no se acepta la cancelación.\n*Las cantidades de producto pueden variar en +/- 10% y deberán ser aceptadas.\n*Condiciones de pago: 50% al hacer el pedido y 50% a contraentrega.',
};

class PdfService {
  static Future<pw.MemoryImage?> _logo() async {
    try {
      final b = await rootBundle.load('assets/logo/logo.png');
      return pw.MemoryImage(b.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, pw.MemoryImage>> _archivosCliente(String clienteId) async {
    final out = <String, pw.MemoryImage>{};
    if (clienteId.isEmpty) return out;
    try {
      final s = await Db.col('clientes').doc(clienteId).collection('archivos').get();
      for (final d in s.docs) {
        final tipo = '${d.data()['tipo']}';
        if (out.containsKey(tipo)) continue;
        try {
          out[tipo] = pw.MemoryImage(base64Decode('${d.data()['dataB64']}'));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  static pw.Widget _kv(String k, String v, {double w = 120}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: w, child: pw.Text(k, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
          pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10))),
        ]),
      );

  // ------------------------------------------------------------- Orden viajera
  static Future<Uint8List> ordenViajera(Rec o) async {
    final doc = pw.Document();
    final logo = await _logo();
    final imgs = await _archivosCliente(o.s('clienteId'));
    final sp = o.m('specs');
    final fechaAp = fmtDate(o.dt('fechaAprobacion'));
    final comp = o.dt('fechaCompromiso');

    String cm(dynamic v) => v == null ? '-' : fmtN(v is num ? v : double.tryParse('$v'), 1);

    pw.Widget box(String titulo, pw.Widget child, {double? h}) => pw.Container(
          height: h,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
            pw.SizedBox(height: 4),
            pw.Expanded(child: child),
          ]),
        );

    final cps = [
      ['1', 'Despacho de materia prima', 'Almacén'],
      ['2', 'Impresión y corte', 'Operador flexo'],
      ['3', 'Inspección de calidad (aprobadas / mermas)', 'Calidad'],
      ['4', 'Armado y pegado manual', 'Armado'],
      ['5', 'Producto terminado / entrega', 'Almacén PT'],
    ];

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(26),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) pw.Image(logo, width: 50, height: 50),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('CARTÓN BOOM', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text('ORDEN VIAJERA · HOJA DE RUTA DE PLANTA', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text(o.s('folio'), style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.Column(children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: o.s('qr', 'CBOT|${o.id}'), width: 120, height: 120),
            pw.Text('Escanear en cada checkpoint', style: const pw.TextStyle(fontSize: 7)),
          ]),
        ]),
        pw.Divider(),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(children: [
              _kv('Cliente', o.s('clienteNombre')),
              _kv('Producto', o.s('producto')),
              _kv('Cantidad requerida', '${fmtI(o.n('cantidad'))} piezas'),
              _kv('Cotización', o.s('cotizacionFolio')),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(children: [
              _kv('Fecha de aprobación', fechaAp),
              _kv('Entrega compromiso', fmtDate(comp)),
              _kv('Láminas estimadas', fmtI(sp['laminasReq'] is num ? sp['laminasReq'] as num : 0)),
              _kv('Entrega', sp['clienteRecoge'] == false ? 'Se envía (flete)' : 'Cliente recoge'),
            ]),
          ),
        ]),
        pw.SizedBox(height: 8),
        box(
          'ESPECIFICACIONES TÉCNICAS',
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(children: [
                _kv('Tipo de caja', '${sp['tipoCaja'] ?? '-'}'),
                _kv('Medidas internas (cm)', '${cm(sp['largo'])} x ${cm(sp['ancho'])} x ${cm(sp['alto'])}'),
                _kv('Lámina de trabajo (cm)', '${cm(sp['laminaLargoCm'])} x ${cm(sp['laminaAnchoCm'])}'),
                _kv('Acabado', '${sp['acabado'] ?? '-'}'),
              ]),
            ),
            pw.Expanded(
              child: pw.Column(children: [
                _kv('Material / Liner', '${sp['material'] ?? '-'}'),
                _kv('Flauta', '${sp['flauta'] ?? '-'}'),
                _kv('ECT', '${sp['ect'] ?? '-'}'),
                _kv('Tintas', '${sp['tintas'] ?? 0}'),
              ]),
            ),
          ]),
          h: 92,
        ),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(
            child: box('DISEÑO / LOGO A IMPRIMIR',
                imgs['logo'] != null ? pw.Center(child: pw.Image(imgs['logo']!, fit: pw.BoxFit.contain)) : pw.Center(child: pw.Text('Sin logo registrado', style: const pw.TextStyle(color: PdfColors.grey))),
                h: 112),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: box('SUAJE / TROQUEL',
                imgs['suaje'] != null ? pw.Center(child: pw.Image(imgs['suaje']!, fit: pw.BoxFit.contain)) : pw.Center(child: pw.Text('N/A', style: const pw.TextStyle(color: PdfColors.grey))),
                h: 112),
          ),
        ]),
        if (o.s('specs').isNotEmpty && '${sp['notas'] ?? ''}'.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text('Notas: ${sp['notas']}', style: const pw.TextStyle(fontSize: 9)),
        ],
        pw.SizedBox(height: 10),
        pw.Text('CONTROL DE CHECKPOINTS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey600),
          columnWidths: {0: const pw.FixedColumnWidth(24), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.5), 4: const pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [for (final h in ['CP', 'Operación', 'Fecha / hora', 'Cantidad', 'Responsable / firma']) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))],
            ),
            for (final c in cps)
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(c[0], style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${c[1]}\n(${c[2]})', style: const pw.TextStyle(fontSize: 9))),
                  pw.SizedBox(height: 30),
                  pw.SizedBox(height: 30),
                  pw.SizedBox(height: 30),
                ],
              ),
          ],
        ),
        pw.Spacer(),
        pw.Text('Documento generado por el sistema Cartón Boom · ${fmtDateTime(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      ]),
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------- Cotización
  static Future<Uint8List> cotizacion(Rec c, Map<String, dynamic> empresa) async {
    final doc = pw.Document();
    final logo = await _logo();
    final inp = c.m('input');
    final res = c.m('resultado');
    final escalas = c.l('escalas');
    final tintas = (inp['tintas'] as List?)?.where((t) => (t is Map) && ((t['cobertura'] ?? 0) as num) > 0).length ?? 0;
    final fecha = c.dt('fecha') ?? DateTime.now();
    final vig = c.i('vigenciaDias', 30);
    final herrAparte = (res['herramentalAparte'] is num) ? (res['herramentalAparte'] as num).toDouble() : 0.0;
    final recoge = inp['clienteRecoge'] != false;

    pw.Widget cell(String t, {bool h = false, pw.TextAlign a = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(t, textAlign: a, style: pw.TextStyle(fontSize: 9, fontWeight: h ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final filas = escalas.isNotEmpty
        ? escalas.map((e) => e as Map).toList()
        : [
            {'cantidad': c.i('cantidad'), 'precioUnitConFlete': res['precioUnitConFlete'] ?? res['precioUnit'], 'total': c.n('subtotal')}
          ];

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(30),
      build: (ctx) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) pw.Image(logo, width: 54, height: 54),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('${empresa['nombre']}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text('${empresa['direccion']}', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('COTIZACIÓN', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('No. ${c.s('folio')}', style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Fecha: ${fmtDate(fecha)}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Vigencia: $vig días', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Text('Atención: ${c.s('clienteNombre')}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey600),
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
              for (final h in ['PRODUCTO', 'MEDIDAS INT. (cm)', 'ECT', 'TINTAS', 'FLAUTA', 'PAPEL', 'VOLUMEN', 'PRECIO UNIT.']) cell(h, h: true)
            ]),
            for (final f in filas)
              pw.TableRow(children: [
                cell('${c.s('producto')}\n${inp['tipo'] ?? ''}'),
                cell('${inp['largo'] ?? '-'} x ${inp['ancho'] ?? '-'} x ${inp['alto'] ?? '-'}'),
                cell('${inp['ect'] ?? '-'}'),
                cell('$tintas'),
                cell('${inp['flauta'] ?? '-'}'),
                cell('${inp['material'] ?? '-'}'),
                cell(fmtI(f['cantidad'] is num ? f['cantidad'] as num : 0)),
                cell(money(f['precioUnitConFlete'] is num ? f['precioUnitConFlete'] as num : 0), a: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(recoge ? '*Precios LAB planta Cartón Boom (el cliente recoge).' : '*El precio incluye el flete a su planta.', style: const pw.TextStyle(fontSize: 9)),
        if (herrAparte > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('*Herramentales (cliché / suaje) por ${money(herrAparte)} se pagan por separado.', style: const pw.TextStyle(fontSize: 9)),
          )
        else if (c.s('requiereHerramental') == 'true')
          pw.Text('*Este producto requiere herramentales, los cuales se pagarán por separado.', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Text('${empresa['leyendas']}', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Text('DATOS BANCARIOS\n\n${empresa['datosBancarios'] ?? ''}', style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(child: pw.Text('CONTACTO\n\n${empresa['contacto'] ?? ''}', style: const pw.TextStyle(fontSize: 9))),
        ]),
      ],
    ));
    return doc.save();
  }

  // --------------------------------------------------------- Etiquetas de código de barras
  static Future<Uint8List> etiquetas(List<Rec> items, {String campoDesc = 'descripcion'}) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) => [
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in items)
            pw.Container(
              width: 180,
              height: 84,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500)),
              child: pw.Column(children: [
                pw.Text(m.s(campoDesc), maxLines: 2, style: const pw.TextStyle(fontSize: 6.5)),
                pw.Spacer(),
                pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: m.id, width: 168, height: 34, textStyle: const pw.TextStyle(fontSize: 8)),
              ]),
            ),
        ]),
      ],
    ));
    return doc.save();
  }

  static Future<void> imprimir(Uint8List bytes, String nombre) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: nombre);
}
