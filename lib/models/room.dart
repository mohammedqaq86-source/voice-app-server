class Room {
  final String title;
  final String image;
  final int users;
  final int speakers;
  final bool hasYoutube;
  final bool isPrivate;
  final String videoId;

  const Room({
    required this.title,
    required this.image,
    required this.users,
    required this.speakers,
    required this.hasYoutube,
    required this.videoId,
    this.isPrivate = false,
  });
}