import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/notification_tile.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  final NotificationService _service = NotificationService();
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    await _service.markAllAsRead(widget.userId);
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17112F),
        title: const Text(
          'مسح جميع الإشعارات',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'هل تريد حذف كل الإشعارات؟',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.clearAll(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return CustomPaint(
            painter: _NotifBgPainter(_bgController.value),
            child: child,
          );
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'الإشعارات',
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
            actions: [
              IconButton(
                tooltip: 'تحديد الكل كمقروء',
                onPressed: _markAllRead,
                icon: const Icon(Icons.done_all_rounded, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'مسح الكل',
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
              ),
            ],
          ),
          body: StreamBuilder<List<AppNotification>>(
            stream: _service.notificationsStream(widget.userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final notifications = snapshot.data ?? [];

              if (notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white.withOpacity(0.25),
                        size: 72,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'لا توجد إشعارات',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notif = notifications[index];
                  return NotificationTile(
                    notification: notif,
                    onTap: () {
                      _service.markAsRead(widget.userId, notif.id);
                    },
                    onDelete: () {
                      _service.deleteNotification(widget.userId, notif.id);
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotifBgPainter extends CustomPainter {
  _NotifBgPainter(this.value);
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

    _wave(canvas, size, value * math.pi * 2, size.height * 0.30, 24,
        const Color(0xFF7B3FE4).withOpacity(0.18), size.height * 0.34);
    _wave(canvas, size, value * math.pi * 2 + 1.7, size.height * 0.58, 28,
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
  bool shouldRepaint(covariant _NotifBgPainter old) => old.value != value;
}
