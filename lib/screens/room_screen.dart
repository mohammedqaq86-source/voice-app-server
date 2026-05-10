import 'package:flutter/material.dart';
import '../models/room.dart';

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
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 30,
                      ),
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
                      icon: const Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),

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
                      child: const Icon(Icons.mic, size: 38),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white12,
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
                    style: TextStyle(fontWeight: FontWeight.bold),
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