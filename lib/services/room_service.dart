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
      'isRealRoom': true,
      'usersCount': 1,
      'speakersCount': 0,
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
      'lastSeen': FieldValue.serverTimestamp(),
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

  Future<void> openRoom({required String roomId}) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'isOpen': true,
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> closeRoom({required String roomId}) async {
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
        .where('isRealRoom', isEqualTo: true)
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
        .snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> roomDocFuture({
    required String roomId,
  }) {
    return _firestore.collection('rooms').doc(roomId).get();
  }

  Future<void> deleteInviteFromUser({
    required String userId,
    required String roomId,
  }) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('invites')
        .doc(roomId)
        .delete();
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

    final kickedRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('kickedUsers')
        .doc(invitedUserId);

    batch.delete(kickedRef);

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

      batch.set(userInviteRef, {
        'isOpen': isOpen,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }


  Future<void> cleanupLegacyRoomMembers({required String roomId}) async {
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final members = await roomRef.collection('members').get();
    final batch = _firestore.batch();
    var hasDeletes = false;

    for (final doc in members.docs) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString().toLowerCase().trim();
      final name = (data['name'] ?? '').toString().toLowerCase().trim();

      final isLegacyFakeUser = userId == 'user_mohammed' ||
          userId == 'mohammed' ||
          userId.startsWith('bot_') ||
          userId.contains('bot') ||
          name.contains('bot');

      if (isLegacyFakeUser) {
        batch.delete(doc.reference);
        hasDeletes = true;
      }
    }

    if (hasDeletes) {
      await batch.commit();
    }
  }

  Future<void> joinRoom({
    required String roomId,
    required String userId,
    required String name,
    required String image,
    bool isLeader = false,
    bool hasMicPermission = false,
  }) async {
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    await cleanupLegacyRoomMembers(roomId: roomId);

    final roomData = roomDoc.data() ?? <String, dynamic>{};
    final ownerId = (roomData['ownerId'] ?? '').toString();
    final isOwner = ownerId.isNotEmpty && ownerId == userId;

    final kickedDoc = await roomRef.collection('kickedUsers').doc(userId).get();
    final inviteDoc = await roomRef.collection('invites').doc(userId).get();

    if (kickedDoc.exists && !inviteDoc.exists && !isOwner) {
      throw Exception('You were removed from this room');
    }

    final batch = _firestore.batch();

    final memberRef = roomRef.collection('members').doc(userId);
    batch.set(memberRef, {
      'userId': userId,
      'name': name,
      'image': image,
      'isLeader': isOwner,
      'isOnline': true,
      'hasMicPermission': isOwner || hasMicPermission,
      'isMicOn': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (inviteDoc.exists) {
      batch.delete(roomRef.collection('kickedUsers').doc(userId));
      batch.delete(roomRef.collection('invites').doc(userId));
      batch.delete(_firestore.collection('users').doc(userId).collection('invites').doc(roomId));
    }

    await batch.commit();
    await ensureSingleLeader(roomId: roomId);
    await updateRoomCounts(roomId: roomId);

    await sendSystemMessage(
      roomId: roomId,
      text: '$name joined the room',
      userId: userId,
      name: name,
      image: image,
      isLeader: isOwner,
    );
  }

  Future<void> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    if (roomId.trim().isEmpty || userId.trim().isEmpty) return;

    final memberRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId);

    final memberDoc = await memberRef.get();
    if (!memberDoc.exists) {
      await updateRoomCounts(roomId: roomId);
      return;
    }

    await memberRef.update({
      'isOnline': false,
      'isMicOn': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    await memberRef.delete();
    await updateRoomCounts(roomId: roomId);
  }

  Future<void> ensureSingleLeader({required String roomId}) async {
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final ownerId = (roomDoc.data()?['ownerId'] ?? '').toString();
    if (ownerId.isEmpty) return;

    final members = await roomRef.collection('members').get();
    final batch = _firestore.batch();

    for (final doc in members.docs) {
      final isOwner = doc.id == ownerId;
      batch.set(doc.reference, {
        'isLeader': isOwner,
        if (isOwner) 'hasMicPermission': true,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> updateRoomCounts({required String roomId}) async {
    await cleanupLegacyRoomMembers(roomId: roomId);

    final membersSnapshot = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .get();

    final realMembers = membersSnapshot.docs.where((doc) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString().toLowerCase();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final isBot = userId.startsWith('bot_') ||
          userId == 'user_mohammed' ||
          userId.contains('bot') ||
          name.contains('bot');
      return !isBot;
    }).toList();

    final speakersCount = realMembers.where((doc) {
      return doc.data()['isMicOn'] == true;
    }).length;

    await _firestore.collection('rooms').doc(roomId).update({
      'usersCount': realMembers.length,
      'speakersCount': speakersCount,
    });
  }

  Future<void> updateMicPermission({
    required String roomId,
    required String userId,
    required bool hasMicPermission,
  }) async {
    final memberRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId);

    final memberDoc = await memberRef.get();
    if (!memberDoc.exists) {
      throw Exception('Room member not found');
    }

    await memberRef.update({
      'hasMicPermission': hasMicPermission,
      if (!hasMicPermission) 'isMicOn': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    await updateRoomCounts(roomId: roomId);
  }

  Future<void> updateMicState({
    required String roomId,
    required String userId,
    required bool isMicOn,
  }) async {
    final memberRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(userId);

    final memberDoc = await memberRef.get();
    if (!memberDoc.exists) return;

    await memberRef.update({
      'isMicOn': isMicOn,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    await updateRoomCounts(roomId: roomId);
  }

  Future<void> kickUser({
    required String roomId,
    required String userId,
    required String name,
    required String image,
  }) async {
    final batch = _firestore.batch();

    final roomRef = _firestore.collection('rooms').doc(roomId);
    final memberRef = roomRef.collection('members').doc(userId);
    final kickedRef = roomRef.collection('kickedUsers').doc(userId);

    batch.delete(memberRef);
    batch.delete(roomRef.collection('invites').doc(userId));
    batch.delete(_firestore.collection('users').doc(userId).collection('invites').doc(roomId));

    batch.set(kickedRef, {
      'userId': userId,
      'name': name,
      'image': image,
      'kickedAt': FieldValue.serverTimestamp(),
      'canRejoinByInviteOnly': true,
    });

    await batch.commit();
    await updateRoomCounts(roomId: roomId);

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
    final isOpen = room['isOpen'] == true;
    final isPrivate = room['isPrivate'] == true;
    final ownerId = (room['ownerId'] ?? '').toString();

    if (!isOpen) return false;
    if (ownerId.isEmpty) return false;
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

    if (kickedDoc.exists && !inviteDoc.exists) return false;
    if (isPrivate && !inviteDoc.exists) return false;

    return true;
  }

  Future<void> transferRoomLeadership({
    required String roomId,
    required String oldOwnerId,
    required String newOwnerId,
    required String newOwnerName,
    required String newOwnerImage,
  }) async {
    if (newOwnerId.trim().isEmpty || newOwnerId == oldOwnerId) return;

    final roomRef = _firestore.collection('rooms').doc(roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final currentOwnerId = (roomDoc.data()?['ownerId'] ?? '').toString();
    if (currentOwnerId != oldOwnerId) {
      throw Exception('Only the current leader can transfer leadership');
    }

    final newOwnerDoc = await roomRef.collection('members').doc(newOwnerId).get();
    if (!newOwnerDoc.exists) {
      throw Exception('New leader is not in the room');
    }

    final members = await roomRef.collection('members').get();
    final batch = _firestore.batch();

    batch.update(roomRef, {
      'ownerId': newOwnerId,
      'ownerName': newOwnerName,
      'ownerImage': newOwnerImage,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in members.docs) {
      final isNewOwner = doc.id == newOwnerId;
      final isOldOwner = doc.id == oldOwnerId;
      batch.update(doc.reference, {
        'isLeader': isNewOwner,
        'hasMicPermission': isNewOwner
            ? true
            : (isOldOwner ? false : (doc.data()['hasMicPermission'] == true)),
        if (isOldOwner) 'isMicOn': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    await updateRoomCounts(roomId: roomId);

    await sendSystemMessage(
      roomId: roomId,
      text: '$newOwnerName is now the room leader',
      userId: newOwnerId,
      name: newOwnerName,
      image: newOwnerImage,
      isLeader: true,
      icon: Icons.workspace_premium_rounded,
    );
  }

  Future<void> sendMessage({
    required String roomId,
    required String userId,
    required String name,
    required String image,
    required String message,
    bool isLeader = false,
    String? replyToName,
    String? replyToMessage,
    List<String> mentions = const [],
  }) async {
    await _firestore.collection('rooms').doc(roomId).collection('messages').add({
      'type': 'message',
      'userId': userId,
      'name': name,
      'image': image,
      'message': message,
      'isLeader': isLeader,
      'replyToName': replyToName,
      'replyToMessage': replyToMessage,
      'mentions': mentions,
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
    await _firestore.collection('rooms').doc(roomId).collection('messages').add({
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

  Stream<DocumentSnapshot<Map<String, dynamic>>> friendLinkStream({
    required String currentUserId,
    required String otherUserId,
  }) {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('socialLinks')
        .doc(otherUserId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> friendsStream({
    required String userId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('socialLinks')
        .where('status', isEqualTo: 'friends')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingFriendRequestsStream({
    required String userId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('socialLinks')
        .where('status', isEqualTo: 'pending_received')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> sentFriendRequestsStream({
    required String userId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('socialLinks')
        .where('status', isEqualTo: 'pending_sent')
        .snapshots();
  }

  Future<void> sendFriendRequest({
    required String fromUserId,
    required String fromName,
    required String fromImage,
    required String toUserId,
    required String toName,
    required String toImage,
  }) async {
    if (fromUserId == toUserId) return;

    final batch = _firestore.batch();

    final fromLink = _firestore
        .collection('users')
        .doc(fromUserId)
        .collection('socialLinks')
        .doc(toUserId);

    final toLink = _firestore
        .collection('users')
        .doc(toUserId)
        .collection('socialLinks')
        .doc(fromUserId);

    batch.set(fromLink, {
      'userId': toUserId,
      'name': toName,
      'image': toImage,
      'status': 'pending_sent',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(toLink, {
      'userId': fromUserId,
      'name': fromName,
      'image': fromImage,
      'status': 'pending_received',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> cancelFriendRequest({
    required String fromUserId,
    required String toUserId,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('users').doc(fromUserId).collection('socialLinks').doc(toUserId));
    batch.delete(_firestore.collection('users').doc(toUserId).collection('socialLinks').doc(fromUserId));
    await batch.commit();
  }

  Future<void> rejectFriendRequest({
    required String currentUserId,
    required String otherUserId,
  }) async {
    await cancelFriendRequest(fromUserId: currentUserId, toUserId: otherUserId);
  }

  Future<void> acceptFriendRequest({
    required String currentUserId,
    required String currentName,
    required String currentImage,
    required String otherUserId,
    required String otherName,
    required String otherImage,
  }) async {
    final batch = _firestore.batch();

    final currentLink = _firestore.collection('users').doc(currentUserId).collection('socialLinks').doc(otherUserId);
    final otherLink = _firestore.collection('users').doc(otherUserId).collection('socialLinks').doc(currentUserId);

    batch.set(currentLink, {
      'userId': otherUserId,
      'name': otherName,
      'image': otherImage,
      'status': 'friends',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(otherLink, {
      'userId': currentUserId,
      'name': currentName,
      'image': currentImage,
      'status': 'friends',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> removeFriend({
    required String currentUserId,
    required String otherUserId,
  }) async {
    await cancelFriendRequest(fromUserId: currentUserId, toUserId: otherUserId);
  }
}
