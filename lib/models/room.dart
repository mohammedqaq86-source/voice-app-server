class Room {
  final String title;
  final String image;
  final int users;
  final int speakers;
  final bool hasYoutube;
  final bool isPrivate;

  const Room({
    required this.title,
    required this.image,
    required this.users,
    required this.speakers,
    required this.hasYoutube,
    this.isPrivate = false,
  });
}