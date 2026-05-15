import 'package:flutter/material.dart';
import '../models/room.dart';
import '../screens/room_screen.dart';
import '../services/room_service.dart';

class RoomCard extends StatefulWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.roomId,
  });

  final Room room;
  final String roomId;

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  final RoomService roomService = RoomService();

  bool isLoading = false;

  final String currentUserId = 'user_mohammed';
  final String currentUserName = 'Mohammed';
  final String currentUserImage = 'https://i.pravatar.cc/150?img=11';

  Future<void> enterRoom() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    try {
      final canEnter = await roomService.canUserEnterRoom(
        roomId: widget.roomId,
        userId: currentUserId,
      );

      if (!mounted) return;

      if (!canEnter) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot enter this room'),
          ),
        );
        return;
      }

      await roomService.joinRoom(
        roomId: widget.roomId,
        userId: currentUserId,
        name: currentUserName,
        image: currentUserImage,
        isLeader: false,
        hasMicPermission: false,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomScreen(
            room: widget.room,
            roomId: widget.roomId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to enter room: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enterRoom,
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Container(
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
                      Image.network(widget.room.image, fit: BoxFit.cover),
                      if (widget.room.hasYoutube)
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
                          widget.room.title,
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
                            const Icon(
                              Icons.people_alt_rounded,
                              size: 18,
                              color: Colors.black45,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.room.users}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.mic_rounded,
                              size: 18,
                              color: Colors.black45,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.room.speakers}',
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
                            widget.room.hasYoutube ? 'YouTube' : 'Voice',
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
          if (isLoading)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}