import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1340),
          title: const Text(
            'تسجيل الخروج',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'هل أنت متأكد من تسجيل الخروج؟',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _AnimatedBg(
          child: SafeArea(
            child: Column(
              children: [
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
                        'الإعدادات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Account info
                      _SectionCard(
                        children: [
                          _SettingTile(
                            icon: Icons.email_rounded,
                            title: 'البريد الإلكتروني',
                            subtitle: user?.email ?? '—',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // App settings (placeholder for future)
                      _SectionCard(
                        children: [
                          _SettingTile(
                            icon: Icons.notifications_rounded,
                            title: 'الإشعارات',
                            subtitle: 'إدارة إشعارات التطبيق',
                            onTap: () {},
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          _SettingTile(
                            icon: Icons.lock_rounded,
                            title: 'الخصوصية',
                            subtitle: 'إعدادات الخصوصية',
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Logout
                      _SectionCard(
                        children: [
                          _SettingTile(
                            icon: Icons.logout_rounded,
                            title: 'تسجيل الخروج',
                            subtitle: 'الخروج من الحساب',
                            iconColor: Colors.redAccent,
                            titleColor: Colors.redAccent,
                            onTap: () => _signOut(context),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          'Voice App v1.0.0',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.25),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor = Colors.white70,
    this.titleColor = Colors.white,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 13))
          : null,
      trailing: onTap != null
          ? const Icon(Icons.chevron_left_rounded, color: Colors.white30)
          : null,
    );
  }
}

class _AnimatedBg extends StatefulWidget {
  const _AnimatedBg({required this.child});

  final Widget child;

  @override
  State<_AnimatedBg> createState() => _AnimatedBgState();
}

class _AnimatedBgState extends State<_AnimatedBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _BgPainter(_ctrl.value),
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.t);

  final double t;

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

    for (final (yRatio, phaseOffset, baseColor, opacity) in [
      (0.28, 0.0, const Color(0xFF7B3FE4), 0.18),
      (0.62, 1.7, const Color(0xFF1E88E5), 0.14),
    ]) {
      final baseY = size.height * yRatio;
      final phase = t * math.pi * 2 + phaseOffset;
      final color = baseColor.withOpacity(opacity);
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 8) {
        final y = baseY +
            math.sin((x / size.width * math.pi * 2) + phase) * 26 +
            math.sin((x / size.width * math.pi * 4) + phase * 0.55) * 7;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, baseY + size.height * 0.38)
        ..lineTo(0, baseY + size.height * 0.38)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => old.t != t;
}
