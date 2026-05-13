import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../widgets/room_card.dart';
import '../widgets/search_box.dart';
import 'room_screen.dart';
import 'youtube_picker_screen.dart';
import 'source_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RoomService roomService = RoomService();

  final String currentUserId = 'user_mohammed';
  final String currentUserName = 'Mohammed';
  final String currentUserImage = 'https://i.pravatar.cc/150?img=11';

  Future<void> openSourcePicker() async {
    final video = await Navigator.push<YoutubeVideo>(
      context,
      MaterialPageRoute(
        builder: (_) => const SourcePickerScreen(),
      ),
    );

    if (video == null) return;

    final roomId = await roomService.createRoom(
      title: video.title,
      image: video.image,
      videoId: 'jfKfPfyJRdk',
      isPrivate: false,
      ownerId: currentUserId,
      ownerName: currentUserName,
      ownerImage: currentUserImage,
    );

    final newRoom = Room(
      title: video.title,
      image: video.image,
      users: 1,
      speakers: 1,
      hasYoutube: true,
      videoId: 'jfKfPfyJRdk',
      isPrivate: false,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          room: newRoom,
          roomId: roomId,
        ),
      ),
    );
  }

  Room roomFromFirestore(Map<String, dynamic> data) {
    return Room(
      title: data['title'] ?? 'Untitled Room',
      image: data['image'] ?? 'https://picsum.photos/400/300',
      users: data['usersCount'] ?? 0,
      speakers: data['speakersCount'] ?? 0,
      hasYoutube: true,
      videoId: data['videoId'] ?? 'jfKfPfyJRdk',
      isPrivate: data['isPrivate'] ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.white.withOpacity(0.92),
          foregroundColor: Colors.black,
          onPressed: openSourcePicker,
          child: const Icon(Icons.add, size: 32),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF20114F),
                Color(0xFF4B245B),
                Color(0xFF102C6B),
                Color(0xFF5A372D),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const HomeHeader(),
                const SearchBox(),
                Expanded(
                  child: StreamBuilder(
                    stream: roomService.publicOpenRoomsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'ما فيه رومات مفتوحة الآن',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final room = roomFromFirestore(data);

                          return RoomCard(
                            room: room,
                            roomId: docs[index].id,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.menu_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          const Text(
            'الرومات العامة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.people_alt_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}