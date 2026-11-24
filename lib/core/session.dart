import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';

/// Sesión + perfil del usuario (rol, estado). Alimenta al router.
class Session extends ChangeNotifier {
  Session._() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
  }
  static final Session I = Session._();

  User? fbUser;
  Map<String, dynamic>? profile;
  bool loading = true;
  StreamSubscription? _authSub;
  StreamSubscription? _profSub;

  void _onAuth(User? u) {
    fbUser = u;
    _profSub?.cancel();
    if (u == null) {
      profile = null;
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    _profSub = FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots().listen((s) {
      profile = s.data();
      loading = false;
      notifyListeners();
    }, onError: (_) {
      loading = false;
      notifyListeners();
    });
  }

  bool get loggedIn => fbUser != null;
  String get role => (profile?['role'] ?? Roles.pendiente).toString();
  bool get active => profile?['activo'] == true && role != Roles.pendiente;
  String get nombre => (profile?['nombre'] ?? fbUser?.email ?? '').toString();
  String get email => fbUser?.email ?? '';
  bool puede(String modulo) => active && Roles.puede(role, modulo);

  Future<void> login(String email, String pass) =>
      FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: pass);

  Future<void> registrar(String nombre, String email, String pass) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.trim(), password: pass);
    await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
      'nombre': nombre.trim(),
      'email': email.trim(),
      'role': Roles.pendiente,
      'activo': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resetPassword(String email) => FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  Future<void> logout() => FirebaseAuth.instance.signOut();
}
