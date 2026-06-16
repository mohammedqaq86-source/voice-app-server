import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/room_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.targetUserId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
  });

  final String targetUserId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;

  bool get isOwnProfile => targetUserId == currentUserId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final RoomService roomService = RoomService();
  late final AnimationController _bgController;

  bool _visitRecorded = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    if (!widget.isOwnProfile) {
      _recordVisit();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _recordVisit() async {
    if (_visitRecorded) return;
    _visitRecorded = true;
    await roomService.recordProfileVisit(
      targetUid: widget.targetUserId,
      visitorId: widget.currentUserId,
      visitorName: widget.currentUserName,
      visitorImage: widget.currentUserImage,
    );
  }

  void _showEditDialog(Map<String, dynamic> profile) {
    final nameCtrl = TextEditingController(text: profile['name'] ?? '');
    final usernameCtrl = TextEditingController(text: profile['username'] ?? '');
    final bioCtrl = TextEditingController(text: profile['bio'] ?? '');
    final countryCtrl = TextEditingController(text: profile['country'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1340),
          title: const Text(
            'تعديل الملف الشخصي',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _editField(nameCtrl, 'الاسم', Icons.person_rounded),
                const SizedBox(height: 12),
                _editField(usernameCtrl, 'المعرف (@username)', Icons.alternate_email_rounded),
                const SizedBox(height: 12),
                _editField(bioCtrl, 'نبذة شخصية', Icons.info_outline_rounded, maxLines: 3),
                const SizedBox(height: 12),
                _editField(countryCtrl, 'الدولة', Icons.flag_rounded),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B3FE4),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await roomService.updateUserProfile(
                  uid: widget.targetUserId,
                  name: nameCtrl.text.trim(),
                  username: usernameCtrl.text.trim(),
                  bio: bioCtrl.text.trim(),
                  country: countryCtrl.text.trim(),
                );
                // Sync Firebase Auth display name
                if (nameCtrl.text.trim().isNotEmpty) {
                  await FirebaseAuth.instance.currentUser
                      ?.updateDisplayName(nameCtrl.text.trim());
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث الملف الشخصي')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _showVisitorsList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          builder: (_, sc) => Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'من زار ملفك الشخصي 👁',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: roomService.profileVisitorsStream(widget.targetUserId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'لم يزر ملفك أحد بعد',
                          style: TextStyle(color: Colors.white60),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data();
                        final name = (data['visitorName'] ?? 'مستخدم').toString();
                        final image = (data['visitorImage'] ?? '').toString();
                        final time = (data['visitTime'] as Timestamp?)?.toDate();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                image.isNotEmpty ? NetworkImage(image) : null,
                            child: image.isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                            backgroundColor: const Color(0xFF2D1F5E),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: time != null
                              ? Text(
                                  _formatTime(time),
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                )
                              : null,
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
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _bgController,
          builder: (context, _) => CustomPaint(
            painter: _ProfileBgPainter(_bgController.value),
            child: SafeArea(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: roomService.userProfileStream(widget.targetUserId),
                builder: (context, snapshot) {
                  final profile = snapshot.data?.data() ?? {};
                  final name = (profile['name'] ?? widget.currentUserName).toString();
                  final username = (profile['username'] ?? '').toString();
                  final bio = (profile['bio'] ?? '').toString();
                  final country = (profile['country'] ?? '').toString();
                  final photoUrl = (profile['photoUrl'] ?? '').toString();
                  final visitCount = (profile['visitCount'] ?? 0) as int;
                  final joinedAt = (profile['joinedAt'] as Timestamp?)?.toDate();

                  return Column(
                    children: [
                      // AppBar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_ios_rounded,
                                  color: Colors.white),
                            ),
                            const Spacer(),
                            const Text(
                              'الملف الشخصي',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            if (widget.isOwnProfile)
                              IconButton(
                                onPressed: () => _showEditDialog(profile),
                                icon: const Icon(Icons.edit_rounded,
                                    color: Colors.white70),
                              )
                            else
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Profile photo + name
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF7B3FE4),
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF7B3FE4).withOpacity(0.4),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 52,
                                      backgroundImage: photoUrl.isNotEmpty
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      backgroundColor: const Color(0xFF2D1F5E),
                                      child: photoUrl.isEmpty
                                          ? const Icon(Icons.person, size: 54, color: Colors.white54)
                                          : null,
                                    ),
                                  ),
                                  if (widget.isOwnProfile)
                                    GestureDetector(
                                      onTap: () => _showEditDialog(profile),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF7B3FE4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.camera_alt_rounded,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),

                              if (username.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '@$username',
                                  style: const TextStyle(
                                    color: Color(0xFF7B3FE4),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],

                              if (bio.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Text(
                                    bio,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Info chips
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (country.isNotEmpty)
                                    _InfoChip(
                                      icon: Icons.flag_rounded,
                                      label: country,
                                    ),
                                  if (joinedAt != null)
                                    _InfoChip(
                                      icon: Icons.calendar_today_rounded,
                                      label:
                                          'انضم ${joinedAt.year}/${joinedAt.month}/${joinedAt.day}',
                                    ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Stats row
                              Row(
                                children: [
                                  Expanded(
                                    child: StreamBuilder<int>(
                                      stream: roomService.friendsCountStream(
                                          widget.targetUserId),
                                      builder: (ctx, snap) => _StatCard(
                                        icon: Icons.people_rounded,
                                        value: '${snap.data ?? 0}',
                                        label: 'صديق',
                                        color: const Color(0xFF1E88E5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StreamBuilder<int>(
                                      stream: roomService.createdRoomsCountStream(
                                          widget.targetUserId),
                                      builder: (ctx, snap) => _StatCard(
                                        icon: Icons.mic_rounded,
                                        value: '${snap.data ?? 0}',
                                        label: 'روم',
                                        color: const Color(0xFF7B3FE4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Eye / visitors card
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: widget.isOwnProfile
                                          ? () => _showVisitorsList(context)
                                          : null,
                                      child: _StatCard(
                                        icon: Icons.remove_red_eye_rounded,
                                        value: '$visitCount',
                                        label: 'زيارة',
                                        color: const Color(0xFFFFA000),
                                        tappable: widget.isOwnProfile,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Action buttons (for other user's profile)
                              if (!widget.isOwnProfile) ...[
                                _ActionButton(
                                  icon: Icons.person_add_rounded,
                                  label: 'إضافة صديق',
                                  color: const Color(0xFF7B3FE4),
                                  onTap: () async {
                                    await roomService.sendFriendRequest(
                                      fromUserId: widget.currentUserId,
                                      fromName: widget.currentUserName,
                                      fromImage: widget.currentUserImage,
                                      toUserId: widget.targetUserId,
                                      toName: name,
                                      toImage: photoUrl,
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('تم إرسال طلب الصداقة')),
                                      );
                                    }
                                  },
                                ),
                              ],

                              if (widget.isOwnProfile) ...[
                                const SizedBox(height: 8),
                                // Visitors preview section
                                _SectionHeader(
                                  title: 'زوار ملفي 👁',
                                  onTap: () => _showVisitorsList(context),
                                ),
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: roomService.profileVisitorsStream(
                                      widget.targetUserId),
                                  builder: (context, snapshot) {
                                    final docs = snapshot.data?.docs ?? [];
                                    if (docs.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Text(
                                          'لم يزر ملفك أحد بعد',
                                          style: TextStyle(
                                              color: Colors.white.withOpacity(0.4)),
                                        ),
                                      );
                                    }
                                    return SizedBox(
                                      height: 70,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: docs.length > 10 ? 10 : docs.length,
                                        itemBuilder: (_, i) {
                                          final data = docs[i].data();
                                          final img =
                                              (data['visitorImage'] ?? '').toString();
                                          final vName =
                                              (data['visitorName'] ?? '').toString();
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(left: 10),
                                            child: Column(
                                              children: [
                                                CircleAvatar(
                                                  radius: 24,
                                                  backgroundImage: img.isNotEmpty
                                                      ? NetworkImage(img)
                                                      : null,
                                                  backgroundColor:
                                                      const Color(0xFF2D1F5E),
                                                  child: img.isEmpty
                                                      ? const Icon(Icons.person,
                                                          color: Colors.white54)
                                                      : null,
                                                ),
                                                const SizedBox(height: 4),
                                                SizedBox(
                                                  width: 52,
                                                  child: Text(
                                                    vName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white60, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.tappable = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (tappable)
            Icon(Icons.keyboard_arrow_down_rounded,
                color: color.withOpacity(0.6), size: 16),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
            const Spacer(),
            const Text(
              'عرض الكل',
              style: TextStyle(color: Color(0xFF7B3FE4), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBgPainter extends CustomPainter {
  _ProfileBgPainter(this.value);

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

    _drawWave(canvas, size,
        phase: value * math.pi * 2,
        baseY: size.height * 0.30,
        amplitude: 26,
        color: const Color(0xFF7B3FE4).withOpacity(0.20),
        height: size.height * 0.36);

    _drawWave(canvas, size,
        phase: value * math.pi * 2 + 1.7,
        baseY: size.height * 0.58,
        amplitude: 30,
        color: const Color(0xFF1E88E5).withOpacity(0.14),
        height: size.height * 0.38);
  }

  void _drawWave(Canvas canvas, Size size,
      {required double phase,
      required double baseY,
      required double amplitude,
      required Color color,
      required double height}) {
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
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileBgPainter old) => old.value != value;
}
