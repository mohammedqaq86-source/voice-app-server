import 'dart:math' as math;

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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final RoomService roomService = RoomService();
  late final AnimationController backgroundController;

  final String currentUserId = 'user_mohammed';
  final String currentUserName = 'Mohammed';
  final String currentUserImage = 'https://i.pravatar.cc/150?img=11';

  @override
  void initState() {
    super.initState();

    backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    backgroundController.dispose();
    super.dispose();
  }

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

  Future<bool> canShowRoom(String roomId) async {
    return roomService.canUserEnterRoom(
      roomId: roomId,
      userId: currentUserId,
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
        body: AnimatedWaveHomeBackground(
          controller: backgroundController,
          child: SafeArea(
            child: Column(
              children: [
                const HomeHeader(),
                const SearchBox(),
                InvitedRoomsSection(
                  roomService: roomService,
                  currentUserId: currentUserId,
                  roomFromFirestore: roomFromFirestore,
                ),
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
                        itemCount: docs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const Padding(
                              padding: EdgeInsets.fromLTRB(4, 2, 4, 10),
                              child: Text(
                                'العام',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            );
                          }

                          final docIndex = index - 1;
                          final roomId = docs[docIndex].id;
                          final data = docs[docIndex].data();
                          final room = roomFromFirestore(data);

                          return FutureBuilder<bool>(
                            future: canShowRoom(roomId),
                            builder: (context, permissionSnapshot) {
                              if (permissionSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox.shrink();
                              }

                              final canShow =
                                  permissionSnapshot.data ?? false;

                              if (!canShow) {
                                return const SizedBox.shrink();
                              }

                              return RoomCard(
                                room: room,
                                roomId: roomId,
                              );
                            },
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

class InvitedRoomsSection extends StatelessWidget {
  const InvitedRoomsSection({
    super.key,
    required this.roomService,
    required this.currentUserId,
    required this.roomFromFirestore,
  });

  final RoomService roomService;
  final String currentUserId;
  final Room Function(Map<String, dynamic> data) roomFromFirestore;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: roomService.myInvitesStream(userId: currentUserId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'خطأ في تحميل الدعوات: ${snapshot.error}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        }

        final invites = snapshot.data?.docs ?? [];

        if (invites.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'المدعوون',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    child: Text(
                      '${invites.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...invites.map((inviteDoc) {
                final invite = inviteDoc.data();
                final roomId = invite['roomId']?.toString() ?? inviteDoc.id;

                return FutureBuilder(
                  future: roomService.roomDocFuture(roomId: roomId),
                  builder: (context, roomSnapshot) {
                    if (roomSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const SizedBox(
                        height: 42,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    if (!roomSnapshot.hasData ||
                        roomSnapshot.data == null ||
                        roomSnapshot.data!.exists == false) {
                      return const SizedBox.shrink();
                    }

                    final roomData = roomSnapshot.data!.data();

                    if (roomData == null || roomData['isOpen'] != true) {
                      return const SizedBox.shrink();
                    }

                    final room = roomFromFirestore(roomData);

                    return Dismissible(
                      key: ValueKey('invite_$roomId'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        height: 128,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.82),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.delete_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        await roomService.deleteInviteFromUser(
                          userId: currentUserId,
                          roomId: roomId,
                        );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم حذف الدعوة'),
                            ),
                          );
                        }

                        return true;
                      },
                      child: RoomCard(
                        room: room,
                        roomId: roomId,
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class AnimatedWaveHomeBackground extends StatelessWidget {
  const AnimatedWaveHomeBackground({
    super.key,
    required this.controller,
    required this.child,
  });

  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          painter: HomeWaveBackgroundPainter(controller.value),
          child: SizedBox.expand(child: child),
        );
      },
    );
  }
}

class HomeWaveBackgroundPainter extends CustomPainter {
  HomeWaveBackgroundPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF170D3F),
          Color(0xFF2B174D),
          Color(0xFF102C6B),
          Color(0xFF4B245B),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, basePaint);

    _drawWave(
      canvas,
      size,
      phase: value * math.pi * 2,
      baseY: size.height * 0.26,
      amplitude: 24,
      color: const Color(0xFF7B3FE4).withOpacity(0.22),
      height: size.height * 0.34,
    );

    _drawWave(
      canvas,
      size,
      phase: value * math.pi * 2 + 1.7,
      baseY: size.height * 0.52,
      amplitude: 30,
      color: const Color(0xFF1E88E5).withOpacity(0.18),
      height: size.height * 0.34,
    );

    _drawWave(
      canvas,
      size,
      phase: value * math.pi * 2 + 3.0,
      baseY: size.height * 0.74,
      amplitude: 22,
      color: const Color(0xFFFFA000).withOpacity(0.11),
      height: size.height * 0.28,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double phase,
    required double baseY,
    required double amplitude,
    required Color color,
    required double height,
  }) {
    final path = Path()..moveTo(0, baseY);

    for (double x = 0; x <= size.width; x += 8) {
      final y = baseY +
          math.sin((x / size.width * math.pi * 2) + phase) * amplitude +
          math.sin((x / size.width * math.pi * 4) + phase * 0.55) *
              (amplitude * 0.28);
      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, baseY + height)
      ..lineTo(0, baseY + height)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HomeWaveBackgroundPainter oldDelegate) {
    return oldDelegate.value != value;
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
            'الرومات',
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