class RoomMemberModel {
  final String userId;
  final String name;
  final String image;

  final bool isLeader;
  final bool isOnline;

  final bool hasMicPermission;
  final bool isMicOn;

  final DateTime? joinedAt;

  RoomMemberModel({
    required this.userId,
    required this.name,
    required this.image,
    required this.isLeader,
    required this.isOnline,
    required this.hasMicPermission,
    required this.isMicOn,
    required this.joinedAt,
  });

  factory RoomMemberModel.fromMap(Map<String, dynamic> map) {
    return RoomMemberModel(
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      image: map['image'] ?? '',

      isLeader: map['isLeader'] ?? false,
      isOnline: map['isOnline'] ?? false,

      hasMicPermission: map['hasMicPermission'] ?? false,
      isMicOn: map['isMicOn'] ?? false,

      joinedAt: map['joinedAt']?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'image': image,

      'isLeader': isLeader,
      'isOnline': isOnline,

      'hasMicPermission': hasMicPermission,
      'isMicOn': isMicOn,

      'joinedAt': joinedAt,
    };
  }
}