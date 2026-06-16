import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  // Cache stream once — prevents re-subscription on every rebuild/animation frame
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  final _bioCtrl = TextEditingController();
  final _bioFocus = FocusNode();

  // ValueNotifiers: local UI state that should NOT trigger StreamBuilder rebuilds
  final _editingBio = ValueNotifier<bool>(false);
  final _savingBio = ValueNotifier<bool>(false);
  final _uploadingAvatar = ValueNotifier<bool>(false);

  // Selection state still uses setState (affects PhotosSection + SelectionBar together)
  bool _selectMode = false;
  final Set<String> _selectedPhotoIds = {};

  bool _visitRecorded = false;

  @override
  void initState() {
    super.initState();

    // Stable stream reference — never recreated on rebuild
    _userStream = roomService.userProfileStream(widget.targetUserId);

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    _bioFocus.addListener(() {
      if (!_bioFocus.hasFocus && _editingBio.value) {
        _saveBio();
      }
    });

    if (!widget.isOwnProfile) {
      _recordVisit();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _bioCtrl.dispose();
    _bioFocus.dispose();
    _editingBio.dispose();
    _savingBio.dispose();
    _uploadingAvatar.dispose();
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

  Future<void> _saveBio() async {
    if (!mounted) return;
    _editingBio.value = false;
    _savingBio.value = true;
    await roomService.updateUserProfile(
      uid: widget.targetUserId,
      bio: _bioCtrl.text.trim(),
    );
    if (mounted) _savingBio.value = false;
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;

    // Only the avatar widget rebuilds — no setState, no StreamBuilder disruption
    _uploadingAvatar.value = true;
    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await roomService.uploadProfileImage(
        uid: widget.targetUserId,
        imageBytes: bytes,
        fileName: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      // Single Firestore write after upload completes
      await roomService.updateUserProfile(
        uid: widget.targetUserId,
        photoUrl: url,
      );
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الصورة: $e')),
        );
      }
    } finally {
      if (mounted) _uploadingAvatar.value = false;
    }
  }

  Future<void> _pickAndAddPhoto() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final visibility = await _askVisibility();
    if (visibility == null || !mounted) return;

    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await roomService.uploadProfileImage(
        uid: widget.targetUserId,
        imageBytes: bytes,
        fileName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await roomService.addProfilePhoto(
        uid: widget.targetUserId,
        url: url,
        visibility: visibility,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إضافة الصورة: $e')),
        );
      }
    }
  }

  Future<String?> _askVisibility() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1340),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'خصوصية الصورة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.public, color: Colors.greenAccent, size: 20),
                ),
                title: const Text('عام', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text('يراها الجميع', style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'public'),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock, color: Colors.orangeAccent, size: 20),
                ),
                title: const Text('خاص', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text('أنت فقط تراها', style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'private'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applySelectionAction(String action) async {
    final ids = List<String>.from(_selectedPhotoIds);
    setState(() {
      _selectMode = false;
      _selectedPhotoIds.clear();
    });
    for (final id in ids) {
      if (action == 'delete') {
        await roomService.deleteProfilePhoto(
            uid: widget.targetUserId, photoId: id);
      } else {
        await roomService.updateProfilePhotoVisibility(
          uid: widget.targetUserId,
          photoId: id,
          visibility: action,
        );
      }
    }
  }

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_\.]+$');

  void _showEditDialog(Map<String, dynamic> profile) {
    final nameCtrl = TextEditingController(text: profile['name'] ?? '');
    final usernameCtrl =
        TextEditingController(text: profile['username'] ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1340),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'تعديل الملف الشخصي',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _editField(nameCtrl, 'الاسم', Icons.person_rounded,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'الاسم مطلوب' : null),
                const SizedBox(height: 12),
                _editField(
                  usernameCtrl,
                  'المعرف (@username)',
                  Icons.alternate_email_rounded,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_\.]')),
                  ],
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) return 'المعرف مطلوب';
                    if (val.length < 3) return '3 أحرف على الأقل';
                    if (val.length > 30) return '30 حرفاً كحد أقصى';
                    if (!_usernameRegex.hasMatch(val)) {
                      return 'أحرف إنجليزية وأرقام فقط';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B3FE4),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx);
                await roomService.updateUserProfile(
                  uid: widget.targetUserId,
                  name: nameCtrl.text.trim(),
                  username: usernameCtrl.text.trim().toLowerCase(),
                );
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
    TextDirection? textDirection,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      textDirection: textDirection,
      inputFormatters: inputFormatters,
      validator: validator,
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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color(0xFF7B3FE4), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.redAccent.withOpacity(0.6), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
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
                  stream:
                      roomService.profileVisitorsStream(widget.targetUserId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: Colors.white),
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
                        final name =
                            (data['visitorName'] ?? 'مستخدم').toString();
                        final image =
                            (data['visitorImage'] ?? '').toString();
                        final time =
                            (data['visitTime'] as Timestamp?)?.toDate();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: image.isNotEmpty
                                ? NetworkImage(image)
                                : null,
                            backgroundColor: const Color(0xFF2D1F5E),
                            child: image.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.white)
                                : null,
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
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
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
        body: Stack(
          children: [
            // Background animation isolated in its own layer — never touches content tree
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (context, _) => CustomPaint(
                  painter: _ProfileBgPainter(_bgController.value),
                ),
              ),
            ),

            // Content layer — completely independent from animation rebuilds
            SafeArea(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userStream,
                builder: (context, snapshot) {
                  final profile = snapshot.data?.data() ?? {};
                  final name =
                      (profile['name'] ?? widget.currentUserName).toString();
                  final username = (profile['username'] ?? '').toString();
                  final bio = (profile['bio'] ?? '').toString();
                  final photoUrl = (profile['photoUrl'] ?? '').toString();

                  // Sync bio text only when not editing
                  if (!_editingBio.value && _bioCtrl.text != bio) {
                    _bioCtrl.text = bio;
                  }

                  return Column(
                    children: [
                      // AppBar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
                            if (widget.isOwnProfile) ...[
                              IconButton(
                                onPressed: () =>
                                    _showVisitorsList(context),
                                icon: const Icon(
                                    Icons.remove_red_eye_rounded,
                                    color: Colors.white70),
                                tooltip: 'زوار ملفي',
                              ),
                              IconButton(
                                onPressed: () => _showEditDialog(profile),
                                icon: const Icon(Icons.edit_rounded,
                                    color: Colors.white70),
                                tooltip: 'تعديل',
                              ),
                            ] else
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      // Selection action bar
                      if (_selectMode)
                        _SelectionBar(
                          count: _selectedPhotoIds.length,
                          onDelete: () => _applySelectionAction('delete'),
                          onPublic: () => _applySelectionAction('public'),
                          onPrivate: () => _applySelectionAction('private'),
                          onCancel: () => setState(() {
                            _selectMode = false;
                            _selectedPhotoIds.clear();
                          }),
                        ),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Avatar — only this widget rebuilds on upload state change
                              ValueListenableBuilder<bool>(
                                valueListenable: _uploadingAvatar,
                                builder: (context, uploading, _) => Stack(
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
                                            color: const Color(0xFF7B3FE4)
                                                .withOpacity(0.4),
                                            blurRadius: 20,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: uploading
                                          ? const Center(
                                              child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2))
                                          : CircleAvatar(
                                              radius: 52,
                                              backgroundImage:
                                                  photoUrl.isNotEmpty
                                                      ? NetworkImage(photoUrl)
                                                      : null,
                                              backgroundColor:
                                                  const Color(0xFF2D1F5E),
                                              child: photoUrl.isEmpty
                                                  ? const Icon(Icons.person,
                                                      size: 54,
                                                      color: Colors.white54)
                                                  : null,
                                            ),
                                    ),
                                    if (widget.isOwnProfile)
                                      GestureDetector(
                                        onTap: uploading
                                            ? null
                                            : _pickAndUploadAvatar,
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF7B3FE4),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 16),
                                        ),
                                      ),
                                  ],
                                ),
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

                              const SizedBox(height: 14),

                              // Bio — only this widget rebuilds on editing/saving state change
                              ValueListenableBuilder<bool>(
                                valueListenable: _editingBio,
                                builder: (context, editing, _) =>
                                    ValueListenableBuilder<bool>(
                                  valueListenable: _savingBio,
                                  builder: (context, saving, _) => _BioSection(
                                    bio: bio,
                                    isOwn: widget.isOwnProfile,
                                    editing: editing,
                                    saving: saving,
                                    controller: _bioCtrl,
                                    focusNode: _bioFocus,
                                    onTap: () {
                                      if (widget.isOwnProfile && !editing) {
                                        _bioCtrl.text = bio;
                                        _editingBio.value = true;
                                        Future.delayed(
                                          const Duration(milliseconds: 50),
                                          () => _bioFocus.requestFocus(),
                                        );
                                      }
                                    },
                                    onSave: _saveBio,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Stats row
                              Row(
                                children: [
                                  Expanded(
                                    child: StreamBuilder<int>(
                                      stream: roomService
                                          .friendsCountStream(
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
                                      stream: roomService
                                          .createdRoomsCountStream(
                                              widget.targetUserId),
                                      builder: (ctx, snap) => _StatCard(
                                        icon: Icons.mic_rounded,
                                        value: '${snap.data ?? 0}',
                                        label: 'روم',
                                        color: const Color(0xFF7B3FE4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Add friend (other profile)
                              if (!widget.isOwnProfile)
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'تم إرسال طلب الصداقة')),
                                      );
                                    }
                                  },
                                ),

                              // Profile photos section
                              _PhotosSection(
                                uid: widget.targetUserId,
                                isOwn: widget.isOwnProfile,
                                roomService: roomService,
                                selectMode: _selectMode,
                                selectedIds: _selectedPhotoIds,
                                onAddPhoto: _pickAndAddPhoto,
                                onLongPress: (id) => setState(() {
                                  _selectMode = true;
                                  _selectedPhotoIds.add(id);
                                }),
                                onTapInSelect: (id) => setState(() {
                                  if (_selectedPhotoIds.contains(id)) {
                                    _selectedPhotoIds.remove(id);
                                    if (_selectedPhotoIds.isEmpty) {
                                      _selectMode = false;
                                    }
                                  } else {
                                    _selectedPhotoIds.add(id);
                                  }
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bio Section ─────────────────────────────────────────────────────────────

class _BioSection extends StatelessWidget {
  const _BioSection({
    required this.bio,
    required this.isOwn,
    required this.editing,
    required this.saving,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onSave,
  });

  final String bio;
  final bool isOwn;
  final bool editing;
  final bool saving;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (!isOwn && bio.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: editing
                ? const Color(0xFF7B3FE4)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: saving
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white38),
                ),
              )
            : editing
                ? TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: null,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSave(),
                  )
                : Text(
                    bio.isEmpty ? 'اكتب نبذة عنك...' : bio,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: bio.isEmpty ? Colors.white30 : Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
      ),
    );
  }
}

// ─── Photos Section ───────────────────────────────────────────────────────────

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({
    required this.uid,
    required this.isOwn,
    required this.roomService,
    required this.selectMode,
    required this.selectedIds,
    required this.onAddPhoto,
    required this.onLongPress,
    required this.onTapInSelect,
  });

  final String uid;
  final bool isOwn;
  final RoomService roomService;
  final bool selectMode;
  final Set<String> selectedIds;
  final VoidCallback onAddPhoto;
  final void Function(String id) onLongPress;
  final void Function(String id) onTapInSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'الصور',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            if (isOwn)
              GestureDetector(
                onTap: onAddPhoto,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B3FE4).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF7B3FE4).withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded,
                          color: Color(0xFF7B3FE4), size: 16),
                      SizedBox(width: 4),
                      Text('إضافة',
                          style: TextStyle(
                              color: Color(0xFF7B3FE4),
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: roomService.profilePhotosStream(uid, isOwner: isOwn),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              if (!isOwn) return const SizedBox.shrink();
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.photo_library_outlined,
                          color: Colors.white.withOpacity(0.2), size: 52),
                      const SizedBox(height: 10),
                      Text(
                        'أضف صورك هنا',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data = docs[i].data();
                final url = (data['url'] as String?) ?? '';
                final vis = (data['visibility'] as String?) ?? 'public';
                final id = docs[i].id;
                final isSelected = selectedIds.contains(id);

                return GestureDetector(
                  onLongPress: isOwn ? () => onLongPress(id) : null,
                  onTap: (selectMode && isOwn) ? () => onTapInSelect(id) : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: url.isNotEmpty
                            ? Image.network(url,
                                fit: BoxFit.cover,
                                loadingBuilder: (_, child, progress) =>
                                    progress == null
                                        ? child
                                        : Container(
                                            color: Colors.white.withOpacity(0.05),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white24),
                                            ),
                                          ))
                            : Container(
                                color: Colors.white.withOpacity(0.05)),
                      ),
                      if (isOwn && vis == 'private')
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.lock,
                                color: Colors.orangeAccent, size: 12),
                          ),
                        ),
                      if (selectMode && isSelected)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B3FE4).withOpacity(0.55),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF7B3FE4), width: 2.5),
                          ),
                          child: const Center(
                            child: Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 30),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─── Selection Bar ────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onPublic,
    required this.onPrivate,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onDelete;
  final VoidCallback onPublic;
  final VoidCallback onPrivate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF1E1340).withOpacity(0.95),
      child: Row(
        children: [
          Text(
            '$count مختار',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onPublic,
            icon: const Icon(Icons.public, size: 14, color: Colors.greenAccent),
            label: const Text('عام',
                style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: onPrivate,
            icon: const Icon(Icons.lock, size: 14, color: Colors.orangeAccent),
            label: const Text('خاص',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 20),
            tooltip: 'حذف',
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded,
                color: Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ─── Background Painter ───────────────────────────────────────────────────────

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
