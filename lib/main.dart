import 'package:flutter/material.dart';
import 'models/room.dart';
import 'widgets/room_card.dart';

void main() {
  runApp(const VoiceApp());
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice App',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  final List<Room> rooms = const [
    Room(
      title: 'سوالف ووناسة',
      image: 'https://picsum.photos/400/300?random=1',
      users: 94,
      speakers: 7,
      hasYoutube: true,
    ),
    Room(
      title: 'جلسة آخر الليل',
      image: 'https://picsum.photos/400/300?random=2',
      users: 76,
      speakers: 5,
      hasYoutube: true,
    ),
    Room(
      title: 'قيمرز الخليج',
      image: 'https://picsum.photos/400/300?random=3',
      users: 52,
      speakers: 4,
      hasYoutube: false,
    ),
    Room(
      title: 'أغاني وسوالف',
      image: 'https://picsum.photos/400/300?random=4',
      users: 41,
      speakers: 3,
      hasYoutube: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F8),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: const Color(0xFF5865F2),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
        body: SafeArea(
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
            icon: const Icon(Icons.menu_rounded, size: 32),
          ),
          const Spacer(),
          const Text(
            'الرومات العامة',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.people_alt_rounded, size: 32),
          ),
        ],
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            SizedBox(width: 18),
            Icon(Icons.search, color: Colors.black45, size: 28),
            SizedBox(width: 10),
            Text(
              'ابحث عن روم أو مستخدم',
              style: TextStyle(
                color: Colors.black45,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}