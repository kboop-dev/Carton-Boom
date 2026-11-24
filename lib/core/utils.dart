import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Documento de Firestore con accesores tolerantes a nulos.
class Rec {
  final String id;
  final Map<String, dynamic> d;
  Rec(this.id, this.d);
  factory Rec.fromSnap(DocumentSnapshot<Map<String, dynamic>> s) => Rec(s.id, s.data() ?? {});

  String s(String k, [String def = '']) => (d[k] ?? def).toString();
  double n(String k, [double def = 0]) {
    final v = d[k];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? def;
  }
  int i(String k, [int def = 0]) => n(k, def.toDouble()).round();
  bool b(String k, [bool def = false]) => d[k] is bool ? d[k] as bool : def;
  DateTime? dt(String k) {
    final v = d[k];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
  Map<String, dynamic> m(String k) => d[k] is Map ? Map<String, dynamic>.from(d[k] as Map) : <String, dynamic>{};
  List<dynamic> l(String k) => d[k] is List ? List<dynamic>.from(d[k] as List) : <dynamic>[];
}

final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$', decimalDigits: 2);
final _moneyInt = NumberFormat.currency(locale: 'es_MX', symbol: '\$', decimalDigits: 0);
String money(num? v, {bool decimals = true}) => v == null ? '-' : (decimals ? _money : _moneyInt).format(v);
String fmtN(num? v, [int dec = 2]) => v == null ? '-' : NumberFormat('#,##0.${'0' * dec}', 'es_MX').format(v);
String fmtI(num? v) => v == null ? '-' : NumberFormat('#,##0', 'es_MX').format(v);
String fmtDate(DateTime? d) => d == null ? '-' : DateFormat('dd/MM/yyyy', 'es_MX').format(d);
String fmtDateTime(DateTime? d) => d == null ? '-' : DateFormat('dd/MM/yyyy HH:mm', 'es_MX').format(d);
String fmtMes(DateTime d) => DateFormat('MMM yy', 'es_MX').format(d);

double toD(String? s, [double def = 0]) => double.tryParse((s ?? '').replaceAll(',', '').trim()) ?? def;

/// Extrae el id de orden de un texto escaneado (QR "CBOT|<id>", folio u id plano).
String normalizaQr(String raw) {
  var t = raw.trim();
  if (t.startsWith('CBOT|')) t = t.substring(5);
  return t;
}

/// Quita asteriscos de Code39 (*CB-MP-001*) y espacios de un código de barras.
String normalizaBarcode(String raw) => raw.trim().replaceAll('*', '').toUpperCase();

DateTime inicioMes(DateTime d) => DateTime(d.year, d.month, 1);
