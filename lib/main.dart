import 'package:flutter/material.dart';

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

class Room {
  final String title;
  final String image;
  final int users;
  final int speakers;
  final bool hasYoutube;

  const Room({
    required this.title,
    required this.image,
    required this.users,
    required this.speakers,
    required this.hasYoutube,
  });
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

class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomScreen(room: room),
          ),
        );
      },
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: 126,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.055),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 132,
              height: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(room.image, fit: BoxFit.cover),
                  if (room.hasYoutube)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded,
                            size: 18, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          '${room.users}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.mic_rounded,
                            size: 18, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          '${room.speakers}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EBFF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        room.hasYoutube ? 'YouTube' : 'Voice',
                        style: const TextStyle(
                          color: Color(0xFF5865F2),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121214),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 74,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 32),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.settings,
                          color: Colors.white, size: 30),
                    ),
                    const Spacer(),
                    const Text(
                      'voice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search,
                          color: Colors.white, size: 30),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.groups_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ],
                ),
              ),

              // YouTube Area
              Container(
                height: 220,
                width: double.infinity,
                color: Colors.black,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 82,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      right: 16,
                      left: 16,
                      child: Text(
                        room.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chat Area
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF2A2A2D),
                  child: ListView(
                    children: const [
                      Text(
                        'محمد دخل الروم',
                        style: TextStyle(color: Colors.white54),
                      ),
                      SizedBox(height: 12),
                      ChatBubble(
                        name: 'فهد',
                        message: 'الصوت واضح؟',
                      ),
                      SizedBox(height: 12),
                      ChatBubble(
                        name: 'ناصر',
                        message: 'شغل المقطع اللي بعده',
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Controls
              Container(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFF3A3A3D),
                child: Row(
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic,
                        size: 38,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        alignment: Alignment.centerRight,
                        child: const Text(
                          'دردش',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.image,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    const Icon(Icons.link,
                        color: Colors.white, size: 28),
                  ],
                ),
              ),

              // Ad Banner
              Container(
                height: 72,
                width: double.infinity,
                color: const Color(0xFF4A4A4D),
                alignment: Alignment.center,
                child: Container(
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'مكان الإعلان',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.name,
    required this.message,
  });

  final String name;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$name: ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: message,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}