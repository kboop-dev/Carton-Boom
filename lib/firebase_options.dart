// ARCHIVO PLACEHOLDER.
// Ejecuta `flutterfire configure` en la raíz del proyecto: sobrescribirá este
// archivo con las llaves reales de TU proyecto de Firebase.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError('Ejecuta flutterfire configure para esta plataforma.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAEpgt9fA-9doG1TiBgl-WI2096DCse8BU',
    appId: '1:944564164348:web:01f8b12a42cffdf30de979',
    messagingSenderId: '944564164348',
    projectId: 'carton-boom',
    authDomain: 'carton-boom.firebaseapp.com',
    storageBucket: 'carton-boom.firebasestorage.app',
    measurementId: 'G-EQFPYKHTJ5',
  );
}
