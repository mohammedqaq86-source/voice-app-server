import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> createRoom({
    required String title,
    required String image,
    required String videoId,
    required bool isPrivate,
    required String ownerId,
    required String ownerName,
    required String ownerImage,
  }) async {
    final doc = await _firestore.collection('rooms').add({
      'title': title,
      'image': image,
      'videoId': videoId,

      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerImage': ownerImage,

      'isPrivate': isPrivate,
      'isOpen': true,

      'usersCount': 1,
      'speakersCount': 1,

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastOpenedAt': FieldValue.serverTimestamp(),
    });

    await doc.collection('members').doc(ownerId).set({
      'userId': ownerId,
      'name': ownerName,
      'image': ownerImage,
      'isLeader': true,
      'isOnline': true,
      'hasMicPermission': true,
      'isMicOn': false,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await sendSystemMessage(
      roomId: doc.id,
      text: '$ownerName joined the room',
      userId: ownerId,
      name: ownerName,
      image: ownerImage,
      isLeader: true,
    );

    return doc.id;
  }

  Future<void> openRoom({
    required String roomId,
  }) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'isOpen': true,
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> closeRoom({
    required String roomId,
  }) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'isOpen': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateRoomVideo({
    required String roomId,
    required String title,
    required String image,
    required String videoId,
  }) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'title': title,
      'image': image,
      'videoId': videoId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> publicOpenRoomsStream() {
    return _firestore
        .collection('rooms')
        .where('isOpen', isEqualTo: true)
        .where('isPrivate', isEqualTo: false)
        .orderBy('lastOpenedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myRoomsStream({
    required String ownerId,
  }) {
    return _firestore
        .collection('rooms')
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myInvitesStream({
    required String userId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('invites')
        .where('isOpen', isEqualTo: true)
        .orderBy('invitedAt', descending: true)
        .snapshots();
  }

  Future<void> inviteUserToRoom({
    required String roomId,
    required String roomTitle,
    required String roomImage,
    required String ownerId,
    required String ownerName,
    required String invitedUserId,
    required String invitedUserName,
    required String invitedUserImage,
  }) async {
    final batch = _firestore.batch();

    final roomInviteRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('invites')
        .doc(invitedUserId);

    final userInviteRef = _firestore
        .collection('users')
        .doc(invitedUserId)
        .collection('invites')
        .doc(roomId);

    batch.set(roomInviteRef, {
      'roomId': roomId,
      'userId': invitedUserId,
      'name': invitedUserName,
      'image': invitedUserImage,
      'invitedBy': ownerId,
      'invitedByName': ownerName,
      'status': 'active',
      'invitedAt': FieldValue.serverTimestamp(),
    });

    batch.set(userInviteRef, {
      'roomId': roomId,
      'roomTitle': roomTitle,
      'roomImage': roomImage,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'isOpen': true,
      'status': 'active',
      'invitedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> syncRoomInviteOpenState({
    required String roomId,
    required bool isOpen,
  }) async {
    final invites = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('invites')
        .get();

    final batch = _firestore.batch();

    for (final invite in invites.docs) {
      final invitedUserId = invite.id;

      final userInviteRef = _firestore
          .collection('users')
          .doc(invitedUserId)
          .collection('invites')
          .doc(roomId);

      batch.update(userInviteRef, {
        'isOpen': isOpen,
      });
    }

    await batch.commit();
  }

  Future<void> joinRoom({
    required String roomId,
    required String userId,
    required String name,
    required String image,
    bool isLeader = false,
    bool hasMicPermission = false,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId)
        .set({
      'userId': userId,
      'name': name,
      'image': image,
      'isLeader': isLeader,
      'isOnline': true,
      'hasMicPermission': hasMicPermission,
      'isMicOn': false,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await sendSystemMessage(
      roomId: roomId,
      text: '$name joined the room',
      userId: userId,
      name: name,
      image: image,
      isLeader: isLeader,
    );
  }

  Future<void> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId)
        .update({
      'isOnline': false,
      'isMicOn': false,
    });
  }

  Future<void> updateMicPermission({
    required String roomId,
    required String userId,
    required bool hasMicPermission,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId)
        .update({
      'hasMicPermission': hasMicPermission,
      if (!hasMicPermission) 'isMicOn': false,
    });
  }

  Future<void> updateMicState({
    required String roomId,
    required String userId,
    required bool isMicOn,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId)
        .update({
      'isMicOn': isMicOn,
    });
  }

  Future<void> kickUser({
    required String roomId,
    required String userId,
    required String name,
    required String image,
  }) async {
    final batch = _firestore.batch();

    final memberRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId);

    final kickedRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('kickedUsers')
        .doc(userId);

    batch.delete(memberRef);

    batch.set(kickedRef, {
      'userId': userId,
      'name': name,
      'image': image,
      'kickedAt': FieldValue.serverTimestamp(),
      'canRejoinByInviteOnly': true,
    });

    await batch.commit();

    await sendSystemMessage(
      roomId: roomId,
      text: '$name was kicked from the room',
      userId: userId,
      name: name,
      image: image,
      customIcon: '🦵',
    );
  }

  Future<bool> canUserEnterRoom({
    required String roomId,
    required String userId,
  }) async {
    final roomDoc = await _firestore.collection('rooms').doc(roomId).get();

    if (!roomDoc.exists) return false;

    final room = roomDoc.data()!;
    final bool isOpen = room['isOpen'] == true;
    final bool isPrivate = room['isPrivate'] == true;
    final String ownerId = room['ownerId'] ?? '';

    if (!isOpen) return false;
    if (ownerId == userId) return true;

    final kickedDoc = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('kickedUsers')
        .doc(userId)
        .get();

    final inviteDoc = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('invites')
        .doc(userId)
        .get();

    if (kickedDoc.exists && !inviteDoc.exists) {
      return false;
    }

    if (isPrivate && !inviteDoc.exists) {
      return false;
    }

    return true;
  }

  Future<void> sendMessage({
    required String roomId,
    required String userId,
    required String name,
    required String image,
    required String message,
    bool isLeader = false,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .add({
      'type': 'message',
      'userId': userId,
      'name': name,
      'image': image,
      'message': message,
      'isLeader': isLeader,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendSystemMessage({
    required String roomId,
    required String text,
    String? userId,
    String? name,
    String? image,
    bool isLeader = false,
    IconData? icon,
    String? customIcon,
  }) async {
    await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .add({
      'type': 'system',
      'text': text,
      'userId': userId,
      'name': name,
      'image': image,
      'isLeader': isLeader,
      'iconCodePoint': icon?.codePoint,
      'iconFontFamily': icon?.fontFamily,
      'customIcon': customIcon,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> membersStream(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .orderBy('isLeader', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(String roomId) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }
}