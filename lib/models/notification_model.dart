import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum NotificationType {
  friendRequest,
  friendAccepted,
  roomInvite,
  micGranted,
  micRevoked,
  leaderTransferred,
  kicked,
  privateMessage,
}

extension NotificationTypeX on NotificationType {
  IconData get icon {
    switch (this) {
      case NotificationType.friendRequest:
        return Icons.person_add_alt_1_rounded;
      case NotificationType.friendAccepted:
        return Icons.people_alt_rounded;
      case NotificationType.roomInvite:
        return Icons.meeting_room_rounded;
      case NotificationType.micGranted:
        return Icons.mic_rounded;
      case NotificationType.micRevoked:
        return Icons.mic_off_rounded;
      case NotificationType.leaderTransferred:
        return Icons.workspace_premium_rounded;
      case NotificationType.kicked:
        return Icons.block_rounded;
      case NotificationType.privateMessage:
        return Icons.chat_bubble_rounded;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.friendRequest:
        return Colors.greenAccent;
      case NotificationType.friendAccepted:
        return Colors.lightBlueAccent;
      case NotificationType.roomInvite:
        return Colors.purpleAccent;
      case NotificationType.micGranted:
        return Colors.greenAccent;
      case NotificationType.micRevoked:
        return Colors.redAccent;
      case NotificationType.leaderTransferred:
        return Colors.amberAccent;
      case NotificationType.kicked:
        return Colors.redAccent;
      case NotificationType.privateMessage:
        return Colors.lightBlueAccent;
    }
  }
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String fromUserId;
  final String fromName;
  final String fromImage;
  final String? roomId;
  final String? roomTitle;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.fromUserId,
    required this.fromName,
    required this.fromImage,
    this.roomId,
    this.roomTitle,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> data, String id) {
    final typeStr = (data['type'] ?? 'friendRequest').toString();
    final type = NotificationType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => NotificationType.friendRequest,
    );
    return AppNotification(
      id: id,
      type: type,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      fromUserId: (data['fromUserId'] ?? '').toString(),
      fromName: (data['fromName'] ?? '').toString(),
      fromImage: (data['fromImage'] ?? '').toString(),
      roomId: data['roomId']?.toString(),
      roomTitle: data['roomTitle']?.toString(),
      isRead: data['isRead'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
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
  };
}
