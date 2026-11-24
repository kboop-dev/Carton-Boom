import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';

const _paleta = [Color(0xFFB07030), Colors.teal, Colors.indigo, Colors.orange, Colors.pink, Colors.green, Colors.blueGrey];

/// Gráfica de barras genérica (etiqueta -> valor).
class BarrasChart extends StatelessWidget {
  final Map<String, double> datos;
  final double alto;
  const BarrasChart(this.datos, {super.key, this.alto = 220});
  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return SizedBox(height: alto, child: const EmptyState('Sin datos'));
    final keys = datos.keys.toList();
    final maxV = datos.values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: alto,
      child: BarChart(BarChartData(
        maxY: maxV * 1.2 + 1,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, m) => Text(fmtI(v), style: const TextStyle(fontSize: 10)))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= keys.length) return const SizedBox();
                final t = keys[i];
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.length > 12 ? '${t.substring(0, 11)}…' : t, style: const TextStyle(fontSize: 9)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < keys.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: datos[keys[i]]!, color: _paleta[i % _paleta.length], width: 18, borderRadius: BorderRadius.circular(4))]),
        ],
      )),
    );
  }
}

class PastelChart extends StatelessWidget {
  final Map<String, double> datos;
  const PastelChart(this.datos, {super.key});
  @override
  Widget build(BuildContext context) {
    final total = datos.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox(height: 180, child: EmptyState('Sin datos'));
    final keys = datos.keys.toList();
    return Row(children: [
      SizedBox(
        height: 180,
        width: 180,
        child: PieChart(PieChartData(sectionsSpace: 2, centerSpaceRadius: 34, sections: [
          for (var i = 0; i < keys.length; i++) PieChartSectionData(value: datos[keys[i]]!, color: _paleta[i % _paleta.length], title: '${(datos[keys[i]]! / total * 100).round()}%', radius: 48, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ])),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < keys.length; i++) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Icon(Icons.circle, size: 10, color: _paleta[i % _paleta.length]), const SizedBox(width: 6), Expanded(child: Text('${keys[i]} (${fmtI(datos[keys[i]]!)})', style: const TextStyle(fontSize: 12)))]))])),
    ]);
  }
}

class LineaChart extends StatelessWidget {
  final List<String> etiquetas;
  final List<double> valores;
  const LineaChart(this.etiquetas, this.valores, {super.key});
  @override
  Widget build(BuildContext context) {
    if (valores.isEmpty) return const SizedBox(height: 200, child: EmptyState('Sin datos'));
    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, m) => Text(fmtI(v), style: const TextStyle(fontSize: 10)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, m) {
            final i = v.toInt();
            return i < 0 || i >= etiquetas.length || v != i.toDouble() ? const SizedBox() : Text(etiquetas[i], style: const TextStyle(fontSize: 9));
          })),
        ),
        lineBarsData: [
          LineChartBarData(spots: [for (var i = 0; i < valores.length; i++) FlSpot(i.toDouble(), valores[i])], isCurved: true, barWidth: 3, color: const Color(0xFFB07030), dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: const Color(0xFFB07030).withOpacity(.12))),
        ],
      )),
    );
  }
}

class MermasPage extends StatelessWidget {
  const MermasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Mermas y calidad',
      subtitle: 'Desperdicio por tipo de trabajo, por tintas (ajustes de máquina) y por causa',
      child: RecStream(
        stream: Db.stream('mermas', orderBy: 'fecha', desc: true, limit: 1000),
        builder: (c, l) {
          if (l.isEmpty) return const EmptyState('Aún no hay mermas registradas. Se generan en el Checkpoint 3 de planta.');
          final porTipo = <String, double>{}, porTintas = <String, double>{}, porCausa = <String, double>{}, porMes = <String, double>{};
          double total = 0, costo = 0;
          final orden = l.reversed.toList();
          for (final m in orden) {
            final q = m.n('cantidad');
            total += q;
            costo += m.n('costo');
            porTipo[m.s('tipoTrabajo', 'N/D').replaceAll('Caja Regular Ranurada (CRR)', 'CRR')] = (porTipo[m.s('tipoTrabajo', 'N/D').replaceAll('Caja Regular Ranurada (CRR)', 'CRR')] ?? 0) + q;
            final tk = m.i('tintas') == 0 ? 'Sin impresión' : '${m.i('tintas')} tinta${m.i('tintas') > 1 ? 's' : ''}';
            porTintas[tk] = (porTintas[tk] ?? 0) + q;
            porCausa[m.s('tipo', 'Producción')] = (porCausa[m.s('tipo', 'Producción')] ?? 0) + q;
            final d = m.dt('fecha');
            if (d != null) porMes[fmtMes(d)] = (porMes[fmtMes(d)] ?? 0) + q;
          }
          return Column(children: [
            ResponsiveGrid(minItemWidth: 220, children: [
              KpiCard(label: 'Láminas desperdiciadas', value: fmtI(total), icon: Icons.recycling, color: Colors.orange),
              KpiCard(label: 'Costo de merma', value: money(costo, decimals: false), icon: Icons.money_off, color: Colors.red),
              KpiCard(label: 'Registros', value: fmtI(l.length), icon: Icons.list_alt),
            ]),
            const SizedBox(height: 12),
            ResponsiveGrid(minItemWidth: 420, children: [
              SectionCard(title: 'Merma por tipo de trabajo', child: BarrasChart(porTipo)),
              SectionCard(title: 'Merma por tiraje de tinta (ajustes de máquina)', child: BarrasChart(porTintas)),
              SectionCard(title: 'Merma por causa', child: PastelChart(porCausa)),
              SectionCard(title: 'Tendencia mensual', child: LineaChart(porMes.keys.toList(), porMes.values.toList())),
            ]),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Últimos registros',
              child: Column(children: [
                for (final m in l.take(40))
                  ListTile(
                    dense: true,
                    title: Text('${m.s('folio')} · ${fmtI(m.n('cantidad'))} láminas · ${m.s('tipo')}'),
                    subtitle: Text('${fmtDateTime(m.dt('fecha'))} · ${m.s('clienteNombre')} · ${m.s('sku')} ${m.s('causa')}'),
                    trailing: Text(money(m.n('costo'))),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
