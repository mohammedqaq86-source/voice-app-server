import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Notifications ────────────────────────────────────────────────────────

  Future<void> sendNotification({
    required String toUserId,
    required String type,
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
      await _firestore
          .collection('users')
          .doc(toUserId)
          .collection('notifications')
          .add({
        'type': type,
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

  // ─── Room CRUD ────────────────────────────────────────────────────────────

  Future<String> createRoom({
    required String title,
    required String image,
    required String videoId,
    required bool isPrivate,
    required String ownerId,
    required String ownerName,
    required String ownerImage,
  }) async {
    // Use a batch so the room doc and the owner's member doc are written
    // atomically.  Any listener that receives the new room document will also
    // see the member document in the same snapshot, eliminating the window
    // where closeRoomIfEmpty could close the room before the first member
    // is written.
    final roomRef = _firestore.collection('rooms').doc();
    final memberRef = roomRef.collection('members').doc(ownerId);

    final batch = _firestore.batch();

    batch.set(roomRef, {
      'title': title,
      'image': image,
      'videoId': videoId,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerImage': ownerImage,
      'isPrivate': isPrivate,
      'isOpen': true,
      'isRealRoom': true,
      'allMicEnabled': false,
      'usersCount': 1,
      'speakersCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastOpenedAt': FieldValue.serverTimestamp(),
    });

    batch.set(memberRef, {
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

    await batch.commit();

    unawaited(sendSystemMessage(
      roomId: roomRef.id,
      text: '$ownerName joined the room',
      userId: ownerId,
      name: ownerName,
      image: ownerImage,
      isLeader: true,
    ));

    unawaited(_recordOpenedRoom(
      userId: ownerId,
      roomId: roomRef.id,
      roomData: {
        'title': title,
        'image': image,
        'ownerId': ownerId,
        'isOpen': true,
        'usersCount': 1,
      },
    ));

    return roomRef.id;
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

  Future<void> updateRoomPrivacy({
    required String roomId,
    required bool isPrivate,
  }) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'isPrivate': isPrivate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> enableMicForAll({required String roomId}) async {
    await _firestore.collection('rooms').doc(roomId).update({
      'allMicEnabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> disableMicForAll({required String roomId}) async {
    final roomRef = _firestore.collection('rooms').doc(roomId);
    final membersSnap = await roomRef.collection('members').get();
    final batch = _firestore.batch();

    batch.update(roomRef, {
      'allMicEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in membersSnap.docs) {
      final data = doc.data();
      if (data['isLeader'] == true) continue;
      batch.update(doc.reference, {
        'isMicOn': false,
        'hasMicPermission': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ─── Streams ──────────────────────────────────────────────────────────────

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

  // Returns rooms the user has ever opened, ordered by last opened time.
  // Uses the per-user openedRooms subcollection which is written by joinRoom.
  Stream<QuerySnapshot<Map<String, dynamic>>> profileRoomsStream(
    String ownerId, {
    bool isOwner = false,
  }) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('openedRooms')
        .orderBy('lastOpenedAt', descending: true)
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

  // ─── Invites ──────────────────────────────────────────────────────────────

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

  // ─── Members ──────────────────────────────────────────────────────────────

  /// Writes a fresh lastSeen + isOnline = true for both the room member doc
  /// and the global user profile so all presence surfaces stay in sync.
  Future<void> updateMemberHeartbeat({
    required String roomId,
    required String userId,
  }) async {
    try {
      final batch = _firestore.batch();

      // Use update (not set+merge) so a delayed or offline-queued heartbeat
      // cannot recreate a member doc that was already deleted on leave.
      // If the doc is gone the batch throws, which we silently swallow below.
      batch.update(
        _firestore
            .collection('rooms')
            .doc(roomId)
            .collection('members')
            .doc(userId),
        {
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        _firestore.collection('users').doc(userId),
        {
          'isOnline': true,
          'currentRoomId': roomId,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {}
  }

  /// Removes members whose lastSeen is older than [staleSeconds] seconds.
  /// Pass [excludeUserId] to protect the user who is currently joining.
  /// Stale members are deleted first; if the owner was among them, leadership
  /// is then transferred to whoever is left (or the room is closed if empty).
  /// Global user presence (isOnline / currentRoomId) is cleared for each
  /// removed member so the users collection stays consistent.
  Future<void> cleanupStaleMembers({
    required String roomId,
    String? excludeUserId,
    int staleSeconds = 75,
  }) async {
    try {
      final threshold = Timestamp.fromDate(
        DateTime.now().subtract(Duration(seconds: staleSeconds)),
      );
      final roomRef = _firestore.collection('rooms').doc(roomId);
      final membersSnap = await roomRef.collection('members').get();

      final stale = membersSnap.docs.where((doc) {
        if (excludeUserId != null && doc.id == excludeUserId) return false;
        final data = doc.data();
        // Remove explicitly offline members (leaveRoom set isOnline:false but
        // the delete may have failed, or the member was set offline by cleanup).
        if (data['isOnline'] == false) return true;
        final lastSeen = data['lastSeen'];
        if (lastSeen == null) return false; // fresh join, server timestamp pending
        return (lastSeen as Timestamp).compareTo(threshold) < 0;
      }).toList();

      if (stale.isEmpty) return;

      // Record whether the current owner is stale before deleting.
      final roomDoc = await roomRef.get();
      final ownerId = (roomDoc.data()?['ownerId'] ?? '').toString();
      final ownerIsStale = stale.any((d) => d.id == ownerId);

      // Delete stale member docs and clear their global presence.
      final batch = _firestore.batch();
      for (final doc in stale) {
        batch.delete(doc.reference);
        batch.set(
          _firestore.collection('users').doc(doc.id),
          {
            'isOnline': false,
            'currentRoomId': null,
            'lastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      // If the owner was stale, hand leadership to whoever remains (or close).
      if (ownerIsStale) {
        await _autoTransferLeadershipOnLeave(
          roomId: roomId,
          leavingUserId: ownerId,
        );
      }

      await updateRoomCounts(roomId: roomId, isOwner: false);
    } catch (_) {
      // Don't block the join operation if cleanup fails.
    }
  }

  /// Called when the current user lands on the home screen (app launch or
  /// return from background).  Removes any stale room membership that was left
  /// behind when the app was killed / crashed while the user was in a room.
  Future<void> cleanupSelfPresence({required String userId}) async {
    if (userId.isEmpty) return;
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final currentRoomId = (data['currentRoomId'] as String?) ?? '';

      if (currentRoomId.isNotEmpty) {
        // leaveRoom handles leadership transfer, member deletion, count
        // updates, and clearing global user presence in one pass.
        await leaveRoom(roomId: currentRoomId, userId: userId);
      } else if (data['isOnline'] == true) {
        // No tracked room but isOnline flag is still set — clear it.
        await _firestore.collection('users').doc(userId).set(
          {
            'isOnline': false,
            'currentRoomId': null,
            'lastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
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
    // Remove members who disappeared without leaving (app killed / connection lost).
    await cleanupStaleMembers(roomId: roomId, excludeUserId: userId);

    final roomRef = _firestore.collection('rooms').doc(roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final roomData = roomDoc.data() ?? <String, dynamic>{};
    final ownerId = (roomData['ownerId'] ?? '').toString();
    final isOwner = ownerId.isNotEmpty && ownerId == userId;

    if (isOwner) {
      await cleanupLegacyRoomMembers(roomId: roomId);
    }

    final kickedDoc = await roomRef.collection('kickedUsers').doc(userId).get();
    final inviteDoc = await roomRef.collection('invites').doc(userId).get();

    if (kickedDoc.exists && !inviteDoc.exists && !isOwner) {
      throw Exception('You were removed from this room');
    }

    final batch = _firestore.batch();

    final memberRef = roomRef.collection('members').doc(userId);
    // Always explicitly set hasMicPermission so rejoining revokes prior grants
    final memberData = <String, dynamic>{
      'userId': userId,
      'name': name,
      'image': image,
      'isLeader': isOwner,
      'isOnline': true,
      'isMicOn': false,
      'hasMicPermission': isOwner,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    };
    batch.set(memberRef, memberData, SetOptions(merge: true));

    // Update global user presence so other screens can see who is in a room.
    batch.set(
      _firestore.collection('users').doc(userId),
      {
        'isOnline': true,
        'currentRoomId': roomId,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (inviteDoc.exists) {
      batch.delete(roomRef.collection('kickedUsers').doc(userId));
      batch.delete(roomRef.collection('invites').doc(userId));
      batch.delete(_firestore.collection('users').doc(userId).collection('invites').doc(roomId));
    }

    await batch.commit();

    if (isOwner) {
      await ensureSingleLeader(roomId: roomId);
    }

    await updateRoomCounts(roomId: roomId, isOwner: isOwner);

    // Record this room in the user's opened-rooms history so the profile page
    // can display it via profileRoomsStream.
    unawaited(_recordOpenedRoom(
      userId: userId,
      roomId: roomId,
      roomData: roomData,
    ));

    await sendSystemMessage(
      roomId: roomId,
      text: '$name joined the room',
      userId: userId,
      name: name,
      image: image,
      isLeader: isOwner,
    );
  }

  Future<void> _recordOpenedRoom({
    required String userId,
    required String roomId,
    required Map<String, dynamic> roomData,
  }) async {
    if (userId.isEmpty || roomId.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('openedRooms')
        .doc(roomId)
        .set({
      'roomId': roomId,
      'title': roomData['title'] ?? '',
      'image': roomData['image'] ?? '',
      'ownerId': roomData['ownerId'] ?? '',
      'isOpen': roomData['isOpen'] ?? false,
      'usersCount': roomData['usersCount'] ?? 0,
      'isRealRoom': true,
      'lastOpenedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    if (roomId.trim().isEmpty || userId.trim().isEmpty) return;

    final roomRef = _firestore.collection('rooms').doc(roomId);
    final memberRef = roomRef.collection('members').doc(userId);

    final memberDoc = await memberRef.get();
    if (!memberDoc.exists) {
      await updateRoomCounts(roomId: roomId, isOwner: false);
      return;
    }

    final memberName = (memberDoc.data()?['name'] ?? 'User').toString();
    final memberImage = (memberDoc.data()?['image'] ?? '').toString();

    // Check if the leaving user is the room owner → auto-transfer leadership
    final roomDoc = await roomRef.get();
    if (roomDoc.exists) {
      final ownerId = (roomDoc.data()?['ownerId'] ?? '').toString();
      if (ownerId == userId) {
        await _autoTransferLeadershipOnLeave(
          roomId: roomId,
          leavingUserId: userId,
        );
      }
    }

    await memberRef.update({
      'isOnline': false,
      'isMicOn': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    await memberRef.delete();

    // Clear global user presence now that the user has left.
    unawaited(_firestore.collection('users').doc(userId).set(
      {
        'isOnline': false,
        'currentRoomId': null,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ));

    // Send a system message so all participants see who left.
    unawaited(sendSystemMessage(
      roomId: roomId,
      text: '$memberName left the room',
      userId: userId,
      name: memberName,
      image: memberImage,
    ));

    // Auto-close room when last member leaves
    final remaining = await roomRef.collection('members').get();
    if (remaining.docs.isEmpty) {
      await roomRef.update({
        'isOpen': false,
        'usersCount': 0,
        'speakersCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Reflect closed state in the leaving user's openedRooms entry.
      unawaited(_firestore
          .collection('users')
          .doc(userId)
          .collection('openedRooms')
          .doc(roomId)
          .set({'isOpen': false, 'usersCount': 0}, SetOptions(merge: true)));
    } else {
      await updateRoomCounts(roomId: roomId, isOwner: false);
    }
  }

  Future<void> _autoTransferLeadershipOnLeave({
    required String roomId,
    required String leavingUserId,
  }) async {
    try {
      final roomRef = _firestore.collection('rooms').doc(roomId);
      final membersSnap = await roomRef
          .collection('members')
          .orderBy('joinedAt')
          .get();

      final remaining = membersSnap.docs
          .where((doc) => doc.id != leavingUserId)
          .toList();

      if (remaining.isEmpty) {
        await roomRef.update({
          'isOpen': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final newLeaderDoc = remaining.first;
      final newLeaderId = newLeaderDoc.id;
      final newLeaderData = newLeaderDoc.data();
      final newLeaderName = (newLeaderData['name'] ?? 'User').toString();
      final newLeaderImage = (newLeaderData['image'] ?? '').toString();

      final batch = _firestore.batch();

      batch.update(roomRef, {
        'ownerId': newLeaderId,
        'ownerName': newLeaderName,
        'ownerImage': newLeaderImage,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final doc in membersSnap.docs) {
        if (doc.id == leavingUserId) continue;
        final isNew = doc.id == newLeaderId;
        batch.update(doc.reference, {
          'isLeader': isNew,
          if (isNew) 'hasMicPermission': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      await sendSystemMessage(
        roomId: roomId,
        text: '$newLeaderName أصبح الليدر الجديد',
        userId: newLeaderId,
        name: newLeaderName,
        image: newLeaderImage,
        isLeader: true,
        icon: Icons.workspace_premium_rounded,
      );

      unawaited(sendNotification(
        toUserId: newLeaderId,
        type: 'leaderTransferred',
        title: 'أنت الليدر الجديد 👑',
        body: 'تم نقل قيادة الروم إليك تلقائياً',
        fromUserId: leavingUserId,
        fromName: newLeaderName,
        fromImage: newLeaderImage,
        roomId: roomId,
      ));
    } catch (_) {
      // Don't block the leave operation if transfer fails
    }
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

  Future<void> updateRoomCounts({required String roomId, bool isOwner = false}) async {
    if (isOwner) {
      await cleanupLegacyRoomMembers(roomId: roomId);
    }

    final membersSnapshot = await _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .get();

    // A member is counted only when they are marked online AND their heartbeat
    // is fresh (lastSeen within 75 seconds — 3× the 25-second heartbeat interval).
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(seconds: 75)),
    );

    final realMembers = membersSnapshot.docs.where((doc) {
      final data = doc.data();

      // Exclude legacy fake users / bots.
      final userId = (data['userId'] ?? doc.id).toString().toLowerCase();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final isBot = userId.startsWith('bot_') ||
          userId == 'user_mohammed' ||
          userId.contains('bot') ||
          name.contains('bot');
      if (isBot) return false;

      // Must be marked online.
      if (data['isOnline'] != true) return false;

      // lastSeen must be recent (or null = server timestamp still pending).
      final lastSeen = data['lastSeen'];
      if (lastSeen == null) return true;
      return (lastSeen as Timestamp).compareTo(cutoff) > 0;
    }).toList();

    final roomRef = _firestore.collection('rooms').doc(roomId);

    // Auto-close the room if no real members remain.
    if (realMembers.isEmpty) {
      await roomRef.update({
        'isOpen': false,
        'usersCount': 0,
        'speakersCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final speakersCount =
        realMembers.where((doc) => doc.data()['isMicOn'] == true).length;

    // Also ensure the room is marked open — guards against a race where the
    // room was briefly seen as empty (e.g. by closeRoomIfEmpty) before all
    // member writes landed.
    await roomRef.update({
      'isOpen': true,
      'usersCount': realMembers.length,
      'speakersCount': speakersCount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Lightweight check called from the rooms list: if a room has no truly
  /// online members it is closed immediately and all stale docs are deleted.
  /// Safe to call in the background — never throws.
  Future<void> closeRoomIfEmpty(String roomId) async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(seconds: 75)),
      );
      final roomRef = _firestore.collection('rooms').doc(roomId);
      final membersSnap = await roomRef.collection('members').get();

      final hasRealMember = membersSnap.docs.any((doc) {
        final data = doc.data();
        if (data['isOnline'] != true) return false;
        final lastSeen = data['lastSeen'];
        if (lastSeen == null) return true; // fresh join
        return (lastSeen as Timestamp).compareTo(cutoff) > 0;
      });

      if (hasRealMember) return;

      // No real member found — delete all stale docs and close the room.
      final batch = _firestore.batch();
      batch.update(roomRef, {
        'isOpen': false,
        'usersCount': 0,
        'speakersCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final doc in membersSnap.docs) {
        batch.delete(doc.reference);
        batch.set(
          _firestore.collection('users').doc(doc.id),
          {
            'isOnline': false,
            'currentRoomId': null,
            'lastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (_) {}
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

    await memberRef.set({
      'hasMicPermission': hasMicPermission,
      if (!hasMicPermission) 'isMicOn': false,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await updateRoomCounts(roomId: roomId, isOwner: false);
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

    await memberRef.set({
      'isMicOn': isMicOn,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await updateRoomCounts(roomId: roomId, isOwner: false);
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
    await updateRoomCounts(roomId: roomId, isOwner: false);

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
    await updateRoomCounts(roomId: roomId, isOwner: false);

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

  // ─── Messages ─────────────────────────────────────────────────────────────

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

  // ─── Friends ──────────────────────────────────────────────────────────────

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

    unawaited(sendNotification(
      toUserId: toUserId,
      type: 'friendRequest',
      title: 'طلب صداقة جديد',
      body: '$fromName أرسل لك طلب صداقة',
      fromUserId: fromUserId,
      fromName: fromName,
      fromImage: fromImage,
    ));
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

    unawaited(sendNotification(
      toUserId: otherUserId,
      type: 'friendAccepted',
      title: 'قبول طلب الصداقة',
      body: '$currentName قبل طلب صداقتك',
      fromUserId: currentUserId,
      fromName: currentName,
      fromImage: currentImage,
    ));
  }

  Future<void> removeFriend({
    required String currentUserId,
    required String otherUserId,
  }) async {
    await cancelFriendRequest(fromUserId: currentUserId, toUserId: otherUserId);
  }

  // ─── Private Chat ─────────────────────────────────────────────────────────

  String privateChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return sorted.join('_');
  }

  Future<void> sendPrivateMessage({
    required String fromUserId,
    required String fromName,
    required String fromImage,
    required String toUserId,
    required String message,
  }) async {
    if (fromUserId.isEmpty || toUserId.isEmpty || fromUserId == toUserId) return;

    final chatId = privateChatId(fromUserId, toUserId);
    final chatRef = _firestore.collection('privateChats').doc(chatId);

    // Write chat doc first so the message security rule can read participants
    await chatRef.set({
      'participants': [fromUserId, toUserId],
      'lastMessage': message,
      'lastMessageFrom': fromUserId,
      'lastMessageFromName': fromName,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'senderId': fromUserId,
      'senderName': fromName,
      'senderImage': fromImage,
      'text': message,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    unawaited(sendNotification(
      toUserId: toUserId,
      type: 'privateMessage',
      title: 'رسالة خاصة من $fromName',
      body: message,
      fromUserId: fromUserId,
      fromName: fromName,
      fromImage: fromImage,
    ));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> privateMessagesStream({
    required String currentUserId,
    required String otherUserId,
  }) {
    final chatId = privateChatId(currentUserId, otherUserId);
    return _firestore
        .collection('privateChats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myPrivateChatsStream({
    required String userId,
  }) {
    return _firestore
        .collection('privateChats')
        .where('participants', arrayContains: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Future<void> markPrivateChatRead({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      final chatId = privateChatId(currentUserId, otherUserId);
      final msgs = await _firestore
          .collection('privateChats')
          .doc(chatId)
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .where('senderId', isEqualTo: otherUserId)
          .get();

      if (msgs.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in msgs.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  Stream<int> unreadPrivateMessagesCount({required String userId}) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .where('type', isEqualTo: 'privateMessage')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ─── User Profile ─────────────────────────────────────────────────────────

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final ref = _firestore.collection('users').doc(uid);
    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'uid': uid,
        'email': email,
        'name': displayName?.isNotEmpty == true ? displayName : email.split('@').first,
        'username': '',
        'bio': '',
        'country': '',
        'photoUrl': photoUrl ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
        'visitCount': 0,
        'sessionToken': '',
      });
    } else {
      // Never overwrite photoUrl for existing users — they manage it via the profile screen.
      // Only sync the display name if not yet set.
      final existingName = (doc.data()?['name'] as String? ?? '').trim();
      final updates = <String, dynamic>{};
      if (existingName.isEmpty && displayName != null && displayName.isNotEmpty) {
        updates['name'] = displayName;
      }
      if (updates.isNotEmpty) await ref.set(updates, SetOptions(merge: true));
    }
  }

  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? username,
    String? bio,
    String? country,
    String? photoUrl,
    String? photoUrlVisibility,
    String? bioVisibility,
    String? photosVisibility,
    bool? allowMatureContent,
    String? onlineVisibility,
    String? joinDateVisibility,
    String? usageVisibility,
    String? chartVisibility,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;
    if (country != null) updates['country'] = country;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (photoUrlVisibility != null) updates['photoUrlVisibility'] = photoUrlVisibility;
    if (bioVisibility != null) updates['bioVisibility'] = bioVisibility;
    if (photosVisibility != null) updates['photosVisibility'] = photosVisibility;
    if (allowMatureContent != null) updates['allowMatureContent'] = allowMatureContent;
    if (onlineVisibility != null) updates['onlineVisibility'] = onlineVisibility;
    if (joinDateVisibility != null) updates['joinDateVisibility'] = joinDateVisibility;
    if (usageVisibility != null) updates['usageVisibility'] = usageVisibility;
    if (chartVisibility != null) updates['chartVisibility'] = chartVisibility;
    if (updates.isEmpty) return;
    await _firestore.collection('users').doc(uid).set(updates, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).get();
  }

  Future<void> recordProfileVisit({
    required String targetUid,
    required String visitorId,
    required String visitorName,
    required String visitorImage,
  }) async {
    if (targetUid == visitorId) return;

    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('profileVisitors')
        .doc(visitorId)
        .set({
      'visitorId': visitorId,
      'visitorName': visitorName,
      'visitorImage': visitorImage,
      'visitTime': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('users').doc(targetUid).set(
      {'visitCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );

    unawaited(sendNotification(
      toUserId: targetUid,
      type: 'profileVisit',
      title: 'زيارة جديدة 👁',
      body: '$visitorName زار ملفك الشخصي',
      fromUserId: visitorId,
      fromName: visitorName,
      fromImage: visitorImage,
    ));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> profileVisitorsStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('profileVisitors')
        .orderBy('visitTime', descending: true)
        .snapshots();
  }

  // ─── Profile Photos ───────────────────────────────────────────────────────

  Future<String> uploadProfileImage({
    required String uid,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final ref = FirebaseStorage.instance.ref('profileImages/$uid/$fileName');
    await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> addProfilePhoto({
    required String uid,
    required String url,
    required String visibility,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('profilePhotos')
        .add({
      'url': url,
      'visibility': visibility,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProfilePhotoVisibility({
    required String uid,
    required String photoId,
    required String visibility,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('profilePhotos')
        .doc(photoId)
        .update({'visibility': visibility});
  }

  Future<void> deleteProfilePhoto({
    required String uid,
    required String photoId,
  }) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('profilePhotos')
        .doc(photoId)
        .get();
    final url = doc.data()?['url'] as String? ?? '';
    await doc.reference.delete();
    if (url.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> profilePhotosStream(
    String uid, {
    bool isOwner = false,
    bool isFriend = false,
  }) {
    final col = _firestore
        .collection('users')
        .doc(uid)
        .collection('profilePhotos');

    if (isOwner) {
      return col.orderBy('createdAt', descending: true).snapshots();
    }
    // Avoid composite index by not using orderBy alongside where.
    if (isFriend) {
      return col.where('visibility', whereIn: ['public', 'friends']).snapshots();
    }
    return col.where('visibility', isEqualTo: 'public').snapshots();
  }

  Stream<int> friendsCountStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('socialLinks')
        .where('status', isEqualTo: 'friends')
        .snapshots()
        .map((s) => s.docs.length);
  }

  Stream<int> createdRoomsCountStream(String uid) {
    return _firestore
        .collection('rooms')
        .where('ownerId', isEqualTo: uid)
        .where('isRealRoom', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ─── Session Management ───────────────────────────────────────────────────

  String _generateSessionToken() {
    final rand = math.Random.secure();
    return List.generate(32, (_) => rand.nextInt(36).toRadixString(36)).join();
  }

  Future<String> updateSessionToken(String uid) async {
    final token = _generateSessionToken();
    await _firestore.collection('users').doc(uid).set(
      {'sessionToken': token},
      SetOptions(merge: true),
    );
    return token;
  }

  Stream<String?> sessionTokenStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.data()?['sessionToken'] as String?);
  }
}
