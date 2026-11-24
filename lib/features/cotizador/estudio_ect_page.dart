import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';

/// Estudio de ECT (Edge Crush Test) requerido por estiba - fórmulas de la hoja "Estudio ECT" del Excel.
class EstudioEctPage extends StatefulWidget {
  const EstudioEctPage({super.key});
  @override
  State<EstudioEctPage> createState() => _EstudioEctPageState();
}

class _EstudioEctPageState extends State<EstudioEctPage> {
  final c = <String, TextEditingController>{
    'l': TextEditingController(text: '35'),
    'a': TextEditingController(text: '29'),
    'h': TextEditingController(text: '20'),
    'peso': TextEditingController(text: '15'),
    'camas': TextEditingController(text: '7'),
    'cajasCama': TextEditingController(text: '1'),
    'pallets': TextEditingController(text: '1'),
    'pesoTarima': TextEditingController(text: '0'),
    'hum': TextEditingController(text: '50'),
    'dias': TextEditingController(text: '90'),
    'area': TextEditingController(text: '100'),
    'calibre': TextEditingController(text: '1'),
  };
  String flauta = 'BC';
  final opts = <String, String>{
    'acomodo': 'Columna ALINEADA',
    'tarima': 'Tarima Buena',
    'colgando': 'Sin cajas colgando',
    'manejo': 'Excesivo',
    'vacios': 'No existen espacios Vacios',
    'flautaH': 'No Aplica',
    'emplayado': 'No Aplica',
    'bases': 'No Aplica',
    'esquineros': 'No Aplica',
    'rejilla': 'No Aplica',
  };

  double v(String k) => toD(c[k]!.text);
  static const _f = {
    'acomodo': {'Columna ALINEADA': 1.0, 'Columna DESALINEADA': 0.85, 'Columna ENTRECRUZADA': 0.4},
    'tarima': {'Tarima Buena': 1.0, 'Tarima Regular': 0.9, 'Tarima Dañada': 0.75},
    'colgando': {'Sin cajas colgando': 1.0, 'Con cajas colgando': 0.6},
    'manejo': {'Moderado': 0.9, 'Excesivo': 0.6, 'Ninguno': 1.0},
    'vacios': {'No existen espacios Vacios': 1.0, 'Si existen espacios Vacios': 0.4},
    'flautaH': {'No Aplica': 1.0, 'Si Aplica': 0.15},
    'emplayado': {'No Aplica': 1.0, 'Si Aplica': 1.3},
    'bases': {'No Aplica': 1.0, 'Si Aplica': 1.3},
    'esquineros': {'No Aplica': 1.0, 'Si Aplica': 1.3},
    'rejilla': {'No Aplica': 1.0, 'Si Aplica': 1.3},
  };
  double f(String k) => _f[k]![opts[k]]!;

  Widget _dd(String k, String label) => dropdown<String>(label, opts[k], _f[k]!.keys.toList(), (x) => setState(() => opts[k] = x!));

  @override
  Widget build(BuildContext context) {
    final e7 = {'E': 1.0, 'B': 1.5, 'C': 2.0, 'BC': 2.5}[flauta]!;
    final perim = (v('l') / 2.54 + v('a') / 2.54) * 2; // in
    final total = v('camas') * v('pallets');
    final sobre = max(0, total - 1);
    final pesoLb = v('peso') * 2.20462;
    final cargaLb = sobre * pesoLb;
    final fSeg = f('acomodo') * f('tarima') * f('colgando') * (1.85 - v('hum') * 0.017) * (0.62 - v('dias') * 0.0006666) * f('manejo') *
        (1.1 - v('area') * 0.0012) * f('vacios') * f('flautaH') * (1 - v('calibre') / 100);
    final fAyuda = f('emplayado') * f('bases') * f('rejilla') * f('esquineros');
    final bct = fSeg == 0 || fAyuda == 0 ? 0.0 : (cargaLb / fSeg + (v('pesoTarima') * 2.20462) / max(1, v('cajasCama'))) / fAyuda; // lbf
    final ectReq = perim <= 0 ? 0.0 : bct / (5.87 * sqrt(e7 * (perim * 0.03937)));
    final ect = max(20, ectReq);

    return PageBody(
      title: 'Estudio ECT',
      subtitle: 'Resistencia requerida según estiba y condiciones de manejo (McKee)',
      child: ResponsiveGrid(minItemWidth: 380, children: [
        SectionCard(title: 'Caja y estiba', child: ResponsiveGrid(minItemWidth: 150, children: [
          for (final e in {'l': 'Largo (cm)', 'a': 'Ancho (cm)', 'h': 'Alto (cm)', 'peso': 'Peso caja con contenido (kg)', 'camas': 'Camas por tarima', 'cajasCama': 'Cajas por cama', 'pallets': 'Núm. de tarimas', 'pesoTarima': 'Peso tarima (kg)'}.entries)
            numField(c[e.key]!, e.value, onChanged: (_) => setState(() {})),
          dropdown<String>('Flauta', flauta, ['E', 'B', 'C', 'BC'], (x) => setState(() => flauta = x!)),
        ])),
        SectionCard(title: 'Factores de manejo y almacenamiento', child: ResponsiveGrid(minItemWidth: 190, children: [
          _dd('acomodo', 'Tipo de acomodo'),
          _dd('tarima', 'Condición de tarima'),
          _dd('colgando', 'Cajas colgando'),
          _dd('manejo', 'Manejo'),
          numField(c['hum']!, 'Humedad (%)', onChanged: (_) => setState(() {})),
          numField(c['dias']!, 'Almacenamiento (días)', onChanged: (_) => setState(() {})),
        ])),
        SectionCard(title: 'Diseño, fabricación y ayudas', child: ResponsiveGrid(minItemWidth: 190, children: [
          numField(c['area']!, '% área impresa', onChanged: (_) => setState(() {})),
          _dd('vacios', 'Espacios vacíos'),
          _dd('flautaH', 'Flauta horizontal'),
          numField(c['calibre']!, 'Pérdida de calibre (milésimas)', onChanged: (_) => setState(() {})),
          _dd('emplayado', 'Emplayado'),
          _dd('bases', 'Bases laminadas'),
          _dd('esquineros', 'Esquineros'),
          _dd('rejilla', 'Rejilla'),
        ])),
        SectionCard(title: 'Resultado', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ECT requerido', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          Text('${fmtN(ect, 1)} lb/in', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Perímetro: ${fmtN(perim, 1)} in · Cajas sobre la primera: ${fmtN(sobre.toDouble(), 0)}'),
          Text('Carga sobre la primera caja: ${fmtN(cargaLb * 0.4535929, 1)} kg'),
          Text('Compresión requerida (BCT): ${fmtN(bct, 1)} lbf'),
          Text('Altura de tarima: ${fmtN(v('h') * v('camas') + 20, 0)} cm'),
          const SizedBox(height: 8),
          const Text('Usa este valor como ECT mínimo en el Cotizador (se redondea hacia arriba al ECT comercial disponible).'),
        ])),
      ]),
    );
  }
}
