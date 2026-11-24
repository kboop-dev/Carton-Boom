import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'utils.dart';

/// Acceso genérico a Firestore con sellos de auditoría.
class Db {
  static final fs = FirebaseFirestore.instance;
  static String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  static CollectionReference<Map<String, dynamic>> col(String c) => fs.collection(c);

  static Map<String, dynamic> stamp(Map<String, dynamic> data, {bool create = false}) => {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
        if (create) 'createdAt': FieldValue.serverTimestamp(),
        if (create) 'createdBy': uid,
      };

  static Stream<List<Rec>> stream(String c, {String? orderBy, bool desc = false, int? limit}) {
    Query<Map<String, dynamic>> q = col(c);
    if (orderBy != null) q = q.orderBy(orderBy, descending: desc);
    if (limit != null) q = q.limit(limit);
    return q.snapshots().map((s) => s.docs.map(Rec.fromSnap).toList());
  }

  static Stream<Rec?> docStream(String c, String id) =>
      col(c).doc(id).snapshots().map((s) => s.exists ? Rec.fromSnap(s) : null);

  static Future<Rec?> get(String c, String id) async {
    final s = await col(c).doc(id).get();
    return s.exists ? Rec.fromSnap(s) : null;
  }

  static Future<List<Rec>> getAll(String c, {String? orderBy, bool desc = false, int? limit}) async {
    Query<Map<String, dynamic>> q = col(c);
    if (orderBy != null) q = q.orderBy(orderBy, descending: desc);
    if (limit != null) q = q.limit(limit);
    final s = await q.get();
    return s.docs.map(Rec.fromSnap).toList();
  }

  static Future<String> add(String c, Map<String, dynamic> data) async =>
      (await col(c).add(stamp(data, create: true))).id;

  static Future<void> set(String c, String id, Map<String, dynamic> data, {bool merge = true, bool create = false}) =>
      col(c).doc(id).set(stamp(data, create: create), SetOptions(merge: merge));

  static Future<void> update(String c, String id, Map<String, dynamic> data) =>
      col(c).doc(id).update(stamp(data));

  static Future<void> delete(String c, String id) => col(c).doc(id).delete();
}
