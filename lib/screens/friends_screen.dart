import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/room_service.dart';
import '../widgets/friend_tile.dart';
import 'private_chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
  });

  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final RoomService _service = RoomService();
  late final AnimationController _bgController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filter(List docs) {
    if (_searchQuery.isEmpty) {
      return docs.map((d) => d.data() as Map<String, dynamic>).toList();
    }
    return docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((data) {
          final name = (data['name'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery);
        })
        .toList();
  }

  Widget _section(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 14),
      ),
    );
  }

  Future<bool> _confirmRemoveFriend(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF21153E),
              title: const Text(
                'إزالة الصديق',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                'هل أنت متأكد من إزالة $name من قائمة أصدقائك؟',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('إزالة', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _openPrivateChat(String otherUserId, String otherName, String otherImage) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserImage: widget.currentUserImage,
          otherUserId: otherUserId,
          otherName: otherName,
          otherImage: otherImage,
        ),
      ),
    );
  }

  Widget _friendsList() {
    return StreamBuilder(
      stream: _service.friendsStream(userId: widget.currentUserId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final items = _filter(docs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('الأصدقاء', items.length),
            if (items.isEmpty)
              _empty('لا يوجد أصدقاء حتى الآن')
            else
              ...List.generate(items.length, (i) {
                final data = items[i];
                final doc = docs[i];
                final otherUserId = (doc.id.isNotEmpty ? doc.id : (data['userId'] ?? '')).toString();
                final otherName = (data['name'] ?? 'User').toString();
                final otherImage = (data['image'] ?? '').toString();
                return FriendTile(
                  name: otherName,
                  image: otherImage,
                  subtitle: 'صديق',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'رسالة خاصة',
                        onPressed: () => _openPrivateChat(otherUserId, otherName, otherImage),
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.lightBlueAccent,
                          size: 22,
                        ),
                      ),
                      IconButton(
                        tooltip: 'إزالة الصديق',
                        onPressed: () async {
                          final confirmed = await _confirmRemoveFriend(otherName);
                          if (!confirmed) return;
                          await _service.removeFriend(
                            currentUserId: widget.currentUserId,
                            otherUserId: otherUserId,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تمت إزالة الصديق')),
                          );
                        },
                        icon: const Icon(
                          Icons.person_remove_rounded,
                          color: Colors.redAccent,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _incomingRequests() {
    return StreamBuilder(
      stream: _service.incomingFriendRequestsStream(userId: widget.currentUserId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final items = _filter(docs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('الطلبات الواردة', items.length),
            if (items.isEmpty)
              _empty('لا توجد طلبات واردة')
            else
              ...List.generate(items.length, (i) {
                final data = items[i];
                final doc = docs[i];
                final otherUserId = (doc.id.isNotEmpty ? doc.id : (data['userId'] ?? '')).toString();
                final otherName = (data['name'] ?? 'User').toString();
                final otherImage = (data['image'] ?? '').toString();
                return FriendTile(
                  name: otherName,
                  image: otherImage,
                  subtitle: 'أرسل لك طلب صداقة',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'قبول',
                        onPressed: () async {
                          await _service.acceptFriendRequest(
                            currentUserId: widget.currentUserId,
                            currentName: widget.currentUserName,
                            currentImage: widget.currentUserImage,
                            otherUserId: otherUserId,
                            otherName: otherName,
                            otherImage: otherImage,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('قبلت طلب $otherName')),
                          );
                        },
                        icon: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.greenAccent,
                          size: 24,
                        ),
                      ),
                      IconButton(
                        tooltip: 'رفض',
                        onPressed: () async {
                          await _service.rejectFriendRequest(
                            currentUserId: widget.currentUserId,
                            otherUserId: otherUserId,
                          );
                        },
                        icon: const Icon(
                          Icons.cancel_rounded,
                          color: Colors.redAccent,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _sentRequests() {
    return StreamBuilder(
      stream: _service.sentFriendRequestsStream(userId: widget.currentUserId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final items = _filter(docs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('الطلبات المرسلة', items.length),
            if (items.isEmpty)
              _empty('لا توجد طلبات مرسلة')
            else
              ...List.generate(items.length, (i) {
                final data = items[i];
                final doc = docs[i];
                final otherUserId = (doc.id.isNotEmpty ? doc.id : (data['userId'] ?? '')).toString();
                final otherName = (data['name'] ?? 'User').toString();
                return FriendTile(
                  name: otherName,
                  image: (data['image'] ?? '').toString(),
                  subtitle: 'في انتظار الرد',
                  trailing: IconButton(
                    tooltip: 'سحب الطلب',
                    onPressed: () async {
                      await _service.cancelFriendRequest(
                        fromUserId: widget.currentUserId,
                        toUserId: otherUserId,
                      );
                    },
                    icon: const Icon(
                      Icons.undo_rounded,
                      color: Colors.orangeAccent,
                      size: 22,
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return CustomPaint(
            painter: _FriendsBgPainter(_bgController.value),
            child: child,
          );
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'الأصدقاء',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  children: [
                    _friendsList(),
                    _incomingRequests(),
                    _sentRequests(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsBgPainter extends CustomPainter {
  _FriendsBgPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF170D3F),
            Color(0xFF2B174D),
            Color(0xFF102C6B),
            Color(0xFF4B245B),
          ],
        ).createShader(rect),
    );
    _wave(canvas, size, value * math.pi * 2, size.height * 0.32, 22,
        const Color(0xFF7B3FE4).withOpacity(0.18), size.height * 0.34);
    _wave(canvas, size, value * math.pi * 2 + 2.1, size.height * 0.62, 26,
        const Color(0xFF1E88E5).withOpacity(0.14), size.height * 0.34);
  }

  void _wave(Canvas canvas, Size size, double phase, double baseY,
      double amp, Color color, double h) {
    final path = Path()..moveTo(0, baseY);
    for (double x = 0; x <= size.width; x += 8) {
      path.lineTo(
        x,
        baseY +
            math.sin((x / size.width * math.pi * 2) + phase) * amp +
            math.sin((x / size.width * math.pi * 4) + phase * 0.55) *
                (amp * 0.28),
      );
    }
    path
      ..lineTo(size.width, baseY + h)
      ..lineTo(0, baseY + h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(covariant _FriendsBgPainter old) => old.value != value;
}
