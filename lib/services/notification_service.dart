import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> send({
    required String toUserId,
    required NotificationType type,
    required String title,
    required String body,
    required String fromUserId,
    required String fromName,
    required String fromImage,
    String? roomId,
    String? roomTitle,
  }) async {
    if (toUserId.isEmpty || toUserId == fromUserId) return;
    try {
      await _db
          .collection('users')
          .doc(toUserId)
          .collection('notifications')
          .add({
        'type': type.name,
        'title': title,
        'body': body,
        'fromUserId': fromUserId,
        'fromName': fromName,
        'fromImage': fromImage,
        if (roomId != null) 'roomId': roomId,
        if (roomTitle != null) 'roomTitle': roomTitle,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<List<AppNotification>> notificationsStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AppNotification.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<int> unreadCountStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markAsRead(String userId, String notifId) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .update({'isRead': true});
    } catch (_) {}
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      final docs = await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();
      if (docs.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in docs.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> deleteNotification(String userId, String notifId) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .delete();
    } catch (_) {}
  }

  Future<void> clearAll(String userId) async {
    try {
      final docs = await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .get();
      if (docs.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in docs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }
}
