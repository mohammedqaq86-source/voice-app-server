class Room {
  final String id;
  final String title;
  final String image;
  final int users;
  final int speakers;
  final bool hasYoutube;
  final bool isPrivate;
  final String videoId;

  final String ownerId;
  final String ownerName;
  final String ownerImage;

  const Room({
    this.id = '',
    required this.title,
    required this.image,
    required this.users,
    required this.speakers,
    required this.hasYoutube,
    required this.videoId,
    this.isPrivate = false,
    this.ownerId = '',
    this.ownerName = '',
    this.ownerImage = '',
  });

  factory Room.fromMap(
    Map<String, dynamic> data, {
    String id = '',
  }) {
    return Room(
      id: id,
      title: data['title'] ?? '',
      image: data['image'] ?? '',
      users: data['usersCount'] ?? data['users'] ?? 0,
      speakers: data['speakersCount'] ?? data['speakers'] ?? 0,
      hasYoutube: data['hasYoutube'] ?? true,
      videoId: data['videoId'] ?? '',
      isPrivate: data['isPrivate'] == true,
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? '',
      ownerImage: data['ownerImage'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'image': image,
      'usersCount': users,
      'speakersCount': speakers,
      'hasYoutube': hasYoutube,
      'videoId': videoId,
      'isPrivate': isPrivate,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerImage': ownerImage,
    };
  }

  Room copyWith({
    String? id,
    String? title,
    String? image,
    int? users,
    int? speakers,
    bool? hasYoutube,
    bool? isPrivate,
    String? videoId,
    String? ownerId,
    String? ownerName,
    String? ownerImage,
  }) {
    return Room(
      id: id ?? this.id,
      title: title ?? this.title,
      image: image ?? this.image,
      users: users ?? this.users,
      speakers: speakers ?? this.speakers,
      hasYoutube: hasYoutube ?? this.hasYoutube,
      isPrivate: isPrivate ?? this.isPrivate,
      videoId: videoId ?? this.videoId,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerImage: ownerImage ?? this.ownerImage,
    );
  }
}