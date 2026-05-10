import 'package:flutter/material.dart';
import '../models/room.dart';
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
  final List<Room> rooms = [
    const Room(
      title: 'سوالف ووناسة',
      image: 'https://picsum.photos/400/300?random=1',
      users: 94,
      speakers: 7,
      hasYoutube: true,
    ),
    const Room(
      title: 'جلسة آخر الليل',
      image: 'https://picsum.photos/400/300?random=2',
      users: 76,
      speakers: 5,
      hasYoutube: true,
    ),
    const Room(
      title: 'قيمرز الخليج',
      image: 'https://picsum.photos/400/300?random=3',
      users: 52,
      speakers: 4,
      hasYoutube: false,
    ),
    const Room(
      title: 'أغاني وسوالف',
      image: 'https://picsum.photos/400/300?random=4',
      users: 41,
      speakers: 3,
      hasYoutube: true,
    ),
  ];

  Future<void> openSourcePicker() async {
    final video = await Navigator.push<YoutubeVideo>(
      context,
      MaterialPageRoute(
        builder: (_) => const SourcePickerScreen(),
      ),
    );

    if (video == null) return;

    final newRoom = Room(
      title: video.title,
      image: video.image,
      users: 1,
      speakers: 1,
      hasYoutube: true,
    );

    setState(() {
      rooms.insert(0, newRoom);
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomScreen(room: newRoom),
      ),
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
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      return RoomCard(room: rooms[index]);
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