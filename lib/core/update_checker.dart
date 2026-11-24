import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'reload_stub.dart' if (dart.library.html) 'reload_web.dart';

/// Detecta cuando se publica una versión nueva en Firebase Hosting
/// (compara /version.json que genera `flutter build web`) y avisa al usuario.
class UpdateChecker {
  UpdateChecker._();
  static final I = UpdateChecker._();

  final ValueNotifier<bool> hayActualizacion = ValueNotifier(false);
  String? _inicial;
  Timer? _timer;

  void start() {
    if (!kIsWeb) return;
    _check();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  Future<String?> _fetch() async {
    try {
      final r = await http.get(Uri.parse('${Uri.base.origin}/version.json?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return '${j['version']}+${j['build_number']}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _check() async {
    final v = await _fetch();
    if (v == null) return;
    _inicial ??= v;
    if (v != _inicial) hayActualizacion.value = true;
  }

  Future<void> actualizar() => hardReload();
}
