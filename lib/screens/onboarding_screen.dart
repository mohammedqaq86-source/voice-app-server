import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/room_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _errorMsg;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_\.]+$');

  @override
  void initState() {
    super.initState();
    // Pre-fill display name from Firebase Auth if available
    final authName = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    if (authName.isNotEmpty) _nameCtrl.text = authName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Check username uniqueness across all users
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(2)
          .get();

      final takenByOther = existing.docs.any((d) => d.id != uid);
      if (takenByOther) {
        setState(() {
          _loading = false;
          _errorMsg = 'هذا المعرف مستخدم مسبقاً، جرب معرفاً آخر';
        });
        return;
      }

      await RoomService().updateUserProfile(uid: uid, name: name, username: username);
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      // AuthGate's profile stream will detect the filled username and route to HomeScreen
    } catch (e) {
      setState(() {
        _errorMsg = 'حدث خطأ، حاول مرة أخرى';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF120B2E),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B3FE4).withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF7B3FE4).withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: Color(0xFF7B3FE4),
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'أكمل ملفك الشخصي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر اسمك ومعرفك الفريد للمتابعة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 36),

                    // Name field
                    TextFormField(
                      controller: _nameCtrl,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _fieldDecoration(
                        hint: 'الاسم المعروض',
                        icon: Icons.person_rounded,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                        if (v.trim().length < 2) return 'الاسم يجب أن يكون حرفين على الأقل';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Username field — Latin only
                    TextFormField(
                      controller: _usernameCtrl,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.text,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\.]')),
                      ],
                      decoration: _fieldDecoration(
                        hint: 'المعرف  (username)',
                        icon: Icons.alternate_email_rounded,
                        prefix: '@',
                      ),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'المعرف مطلوب';
                        if (val.length < 3) return 'يجب أن يكون 3 أحرف على الأقل';
                        if (val.length > 30) return 'يجب أن يكون 30 حرفاً كحد أقصى';
                        if (!_usernameRegex.hasMatch(val)) {
                          return 'أحرف إنجليزية وأرقام و _ و . فقط';
                        }
                        return null;
                      },
                    ),

                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.redAccent.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _complete,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B3FE4),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'ابدأ الاستخدام',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              await FirebaseAuth.instance.signOut();
                            },
                      child: const Text(
                        'تسجيل الخروج',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? prefix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      prefix: prefix != null
          ? Text(prefix,
              style: const TextStyle(
                  color: Color(0xFF7B3FE4), fontWeight: FontWeight.w700))
          : null,
      filled: true,
      fillColor: Colors.white.withOpacity(0.07),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            const BorderSide(color: Color(0xFF7B3FE4), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: Colors.redAccent.withOpacity(0.6), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
    );
  }
}
