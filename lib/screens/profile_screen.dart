import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import 'room_screen.dart';

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
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  // Bio editing
  final _bioCtrl = TextEditingController();
  final _bioFocus = FocusNode();
  final _editingBio = ValueNotifier<bool>(false);
  final _savingBio = ValueNotifier<bool>(false);

  // Name inline editing
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _editingName = ValueNotifier<bool>(false);
  final _savingName = ValueNotifier<bool>(false);

  // Username inline editing
  final _userCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _editingUsername = ValueNotifier<bool>(false);
  final _savingUsername = ValueNotifier<bool>(false);

  // 14-day restriction — kept in sync from the profile stream
  Timestamp? _lastUsernameChangeAt;

  // Avatar upload
  final _uploadingAvatar = ValueNotifier<bool>(false);

  // Photo selection
  bool _selectMode = false;
  final Set<String> _selectedPhotoIds = {};

  bool _visitRecorded = false;
  bool _isFriend = false;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_\.]+$');

  @override
  void initState() {
    super.initState();
    _userStream = roomService.userProfileStream(widget.targetUserId);
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    _bioFocus.addListener(() {
      if (!_bioFocus.hasFocus && _editingBio.value) _saveBio();
    });
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingName.value) _saveName();
    });
    _userFocus.addListener(() {
      if (!_userFocus.hasFocus && _editingUsername.value) _commitUsername();
    });

    if (!widget.isOwnProfile) {
      _recordVisit();
      _checkFriendship();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _bioCtrl.dispose();
    _bioFocus.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _userCtrl.dispose();
    _userFocus.dispose();
    _editingBio.dispose();
    _savingBio.dispose();
    _editingName.dispose();
    _savingName.dispose();
    _editingUsername.dispose();
    _savingUsername.dispose();
    _uploadingAvatar.dispose();
    super.dispose();
  }

  // ── Friendship ──────────────────────────────────────────────────────────────

  Future<void> _checkFriendship() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .collection('socialLinks')
        .doc(widget.targetUserId)
        .get();
    if (mounted) {
      setState(() => _isFriend = doc.data()?['status'] == 'friends');
    }
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

  // ── Bio ─────────────────────────────────────────────────────────────────────

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

  // ── Name inline edit ────────────────────────────────────────────────────────

  Future<void> _saveName() async {
    if (!mounted) return;
    _editingName.value = false;
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    _savingName.value = true;
    await roomService.updateUserProfile(uid: widget.targetUserId, name: newName);
    await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
    if (mounted) _savingName.value = false;
  }

  // ── Username inline edit (14-day restriction) ───────────────────────────────

  Future<void> _commitUsername() async {
    if (!mounted) return;
    _editingUsername.value = false;
    final current = _userCtrl.text.trim().toLowerCase();
    await _saveUsername(current);
  }

  Future<void> _saveUsername(String newUser) async {
    if (!mounted) return;

    // Format validation
    if (newUser.length < 3 ||
        newUser.length > 30 ||
        !_usernameRegex.hasMatch(newUser)) {
      _showSnack('المعرف غير صالح: 3-30 حرفاً إنجليزية وأرقام فقط');
      return;
    }

    // 14-day restriction check
    if (_lastUsernameChangeAt != null) {
      final days =
          DateTime.now().difference(_lastUsernameChangeAt!.toDate()).inDays;
      if (days < 14) {
        _showSnack('يمكنك تغيير المعرف بعد ${14 - days} يوم');
        return;
      }
    }

    _savingUsername.value = true;
    await roomService.updateUserProfile(
        uid: widget.targetUserId, username: newUser);
    // Record the change timestamp
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.targetUserId)
        .set({'lastUsernameChangeAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    if (mounted) _savingUsername.value = false;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Avatar ──────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;

    _uploadingAvatar.value = true;
    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await roomService.uploadProfileImage(
        uid: widget.targetUserId,
        imageBytes: bytes,
        fileName: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await roomService.updateUserProfile(uid: widget.targetUserId, photoUrl: url);
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
    } catch (e) {
      _showSnack('فشل رفع الصورة: $e');
    } finally {
      if (mounted) _uploadingAvatar.value = false;
    }
  }

  // ── Photos ──────────────────────────────────────────────────────────────────

  Future<void> _pickAndAddPhoto() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final visibility = await _showPrivacySheet(context);
    if (visibility == null || !mounted) return;

    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await roomService.uploadProfileImage(
        uid: widget.targetUserId,
        imageBytes: bytes,
        fileName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await roomService.addProfilePhoto(
          uid: widget.targetUserId, url: url, visibility: visibility);
    } catch (e) {
      _showSnack('فشل إضافة الصورة: $e');
    }
  }

  static Future<String?> _showPrivacySheet(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1340),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'خصوصية الصورة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _PrivacyOption(
                icon: Icons.remove_red_eye_rounded,
                label: 'العام',
                subtitle: 'يراها الجميع',
                onTap: () => Navigator.pop(ctx, 'public'),
              ),
              _PrivacyOption(
                icon: Icons.people_rounded,
                label: 'الأصدقاء',
                subtitle: 'الأصدقاء فقط',
                onTap: () => Navigator.pop(ctx, 'friends'),
              ),
              _PrivacyOption(
                icon: Icons.visibility_off_rounded,
                label: 'مخفي',
                subtitle: 'أنت فقط تراها',
                onTap: () => Navigator.pop(ctx, 'hidden'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changePhotoVisibility(String photoId) async {
    final newVis = await _showPrivacySheet(context);
    if (newVis == null || !mounted) return;
    await roomService.updateProfilePhotoVisibility(
      uid: widget.targetUserId,
      photoId: photoId,
      visibility: newVis,
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

  // ── Visitors list ────────────────────────────────────────────────────────────

  void _showVisitorsList() {
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
                              CircularProgressIndicator(color: Colors.white));
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('لم يزر ملفك أحد بعد',
                            style: TextStyle(color: Colors.white60)),
                      );
                    }
                    return ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data();
                        final vName =
                            (data['visitorName'] ?? 'مستخدم').toString();
                        final vImage =
                            (data['visitorImage'] ?? '').toString();
                        final time =
                            (data['visitTime'] as Timestamp?)?.toDate();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: vImage.isNotEmpty
                                ? NetworkImage(vImage)
                                : null,
                            backgroundColor: const Color(0xFF2D1F5E),
                            child: vImage.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.white)
                                : null,
                          ),
                          title: Text(vName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          subtitle: time != null
                              ? Text(_fmtTime(time),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12))
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

  // ── Rooms navigation ─────────────────────────────────────────────────────────

  Future<void> _openRoom(Map<String, dynamic> roomData, String roomId) async {
    final isOpen = roomData['isOpen'] == true;
    if (!isOpen) {
      await roomService.openRoom(roomId: roomId);
    }
    if (!mounted) return;
    final room = Room.fromMap(roomData, id: roomId);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomScreen(room: room, roomId: roomId)),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _fmtTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  bool _canViewStat(String visibility) {
    if (widget.isOwnProfile) return true;
    if (visibility == 'public') return true;
    if (visibility == 'friends' && _isFriend) return true;
    return false;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Animated gradient background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (_, __) => CustomPaint(
                  painter: _ProfileBgPainter(_bgController.value),
                ),
              ),
            ),

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
                  final photoUrlVis =
                      (profile['photoUrlVisibility'] ?? 'public').toString();
                  final bioVis =
                      (profile['bioVisibility'] ?? 'public').toString();
                  final onlineVis =
                      (profile['onlineVisibility'] ?? 'public').toString();
                  final joinDateVis =
                      (profile['joinDateVisibility'] ?? 'public').toString();
                  final usageVis =
                      (profile['usageVisibility'] ?? 'public').toString();
                  final chartVis =
                      (profile['chartVisibility'] ?? 'public').toString();
                  final isOnline = profile['isOnline'] == true;
                  final joinedAt = profile['joinedAt'] as Timestamp?;
                  final usageHours =
                      (profile['usageHours'] as num?)?.toInt() ?? 0;
                  final country = (profile['country'] ?? '').toString();

                  // Keep restriction timestamp in sync
                  _lastUsernameChangeAt =
                      profile['lastUsernameChangeAt'] as Timestamp?;

                  // Sync bio/name/username only when not editing
                  if (!_editingBio.value && _bioCtrl.text != bio) {
                    _bioCtrl.text = bio;
                  }
                  if (!_editingName.value && !_savingName.value) {
                    _nameCtrl.text = name;
                  }
                  if (!_editingUsername.value && !_savingUsername.value) {
                    _userCtrl.text = username;
                  }

                  final canViewAvatar = widget.isOwnProfile ||
                      photoUrlVis == 'public' ||
                      (photoUrlVis == 'friends' && _isFriend);

                  // ── Name inline widget ──────────────────────────────────
                  final nameWidget = ValueListenableBuilder<bool>(
                    valueListenable: _editingName,
                    builder: (_, editingN, __) =>
                        ValueListenableBuilder<bool>(
                      valueListenable: _savingName,
                      builder: (_, savingN, __) => _InlineTextField(
                        value: name,
                        isEditing: editingN,
                        isSaving: savingN,
                        isOwn: widget.isOwnProfile,
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                        onTap: () {
                          _nameCtrl.text = name;
                          _editingName.value = true;
                          Future.delayed(
                            const Duration(milliseconds: 50),
                            () => _nameFocus.requestFocus(),
                          );
                        },
                        onSubmit: _saveName,
                      ),
                    ),
                  );

                  // ── Username inline widget ──────────────────────────────
                  final usernameWidget = ValueListenableBuilder<bool>(
                    valueListenable: _editingUsername,
                    builder: (_, editingU, __) =>
                        ValueListenableBuilder<bool>(
                      valueListenable: _savingUsername,
                      builder: (_, savingU, __) => _InlineTextField(
                        value: username.isEmpty ? '' : '@$username',
                        isEditing: editingU,
                        isSaving: savingU,
                        isOwn: widget.isOwnProfile,
                        controller: _userCtrl,
                        focusNode: _userFocus,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9_\.]')),
                        ],
                        textStyle: const TextStyle(
                          color: Color(0xFF9B72F0),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        onTap: () {
                          _userCtrl.text = username;
                          _editingUsername.value = true;
                          Future.delayed(
                            const Duration(milliseconds: 50),
                            () => _userFocus.requestFocus(),
                          );
                        },
                        onSubmit: _commitUsername,
                      ),
                    ),
                  );

                  return Column(
                    children: [
                      // ── AppBar ──────────────────────────────────────────
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
                            if (widget.isOwnProfile)
                              IconButton(
                                onPressed: _showVisitorsList,
                                icon: const Icon(Icons.remove_red_eye_rounded,
                                    color: Colors.white70),
                                tooltip: 'زوار ملفي',
                              )
                            else
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      // ── Selection bar ───────────────────────────────────
                      if (_selectMode)
                        _SelectionBar(
                          count: _selectedPhotoIds.length,
                          onDelete: () => _applySelectionAction('delete'),
                          onPublic: () => _applySelectionAction('public'),
                          onFriends: () => _applySelectionAction('friends'),
                          onHidden: () => _applySelectionAction('hidden'),
                          onCancel: () => setState(() {
                            _selectMode = false;
                            _selectedPhotoIds.clear();
                          }),
                        ),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                          child: Column(
                            children: [
                              // ── Profile Header ──────────────────────────
                              _ProfileHeader(
                                photoUrl: canViewAvatar ? photoUrl : '',
                                photoUrlVisibility: photoUrlVis,
                                isOnline: isOnline,
                                isOwn: widget.isOwnProfile,
                                country: country,
                                uploadingAvatar: _uploadingAvatar,
                                onPickAvatar: _pickAndUploadAvatar,
                                onChangeAvatarVis: () async {
                                  final newVis =
                                      await _showPrivacySheet(context);
                                  if (newVis != null && mounted) {
                                    await roomService.updateUserProfile(
                                      uid: widget.targetUserId,
                                      photoUrlVisibility: newVis,
                                    );
                                  }
                                },
                                nameWidget: nameWidget,
                                usernameWidget: usernameWidget,
                              ),

                              const SizedBox(height: 14),

                              // ── Bio section ─────────────────────────────
                              _SectionCard(
                                icon: Icons.person_outline_rounded,
                                title: 'السيرة الذاتية',
                                visibility:
                                    widget.isOwnProfile ? bioVis : null,
                                onVisibilityTap: widget.isOwnProfile
                                    ? () async {
                                        final v = await _showPrivacySheet(
                                            context);
                                        if (v != null && mounted) {
                                          await roomService.updateUserProfile(
                                            uid: widget.targetUserId,
                                            bioVisibility: v,
                                          );
                                        }
                                      }
                                    : null,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _editingBio,
                                  builder: (_, editing, __) =>
                                      ValueListenableBuilder<bool>(
                                    valueListenable: _savingBio,
                                    builder: (_, saving, __) => _BioContent(
                                      bio: bio,
                                      isOwn: widget.isOwnProfile,
                                      canView: widget.isOwnProfile ||
                                          _canViewStat(bioVis),
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
                              ),

                              const SizedBox(height: 12),

                              // ── Photos section ──────────────────────────
                              StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream: roomService.profilePhotosStream(
                                  widget.targetUserId,
                                  isOwner: widget.isOwnProfile,
                                  isFriend: _isFriend,
                                ),
                                builder: (context, photoSnap) {
                                  final photoDocs =
                                      photoSnap.data?.docs ?? [];
                                  return Column(
                                    children: [
                                      _SectionCard(
                                        icon: Icons.photo_library_rounded,
                                        title: 'الصور (${photoDocs.length})',
                                        showMenu: true,
                                        child: photoDocs.isEmpty &&
                                                !widget.isOwnProfile
                                            ? const SizedBox(
                                                height: 60,
                                                child: Center(
                                                  child: Text(
                                                    'لا توجد صور',
                                                    style: TextStyle(
                                                        color: Colors.white38,
                                                        fontSize: 13),
                                                  ),
                                                ),
                                              )
                                            : _PhotosGrid(
                                                docs: photoDocs,
                                                isOwn: widget.isOwnProfile,
                                                selectMode: _selectMode,
                                                selectedIds: _selectedPhotoIds,
                                                onAddPhoto: _pickAndAddPhoto,
                                                onEyeTap:
                                                    _changePhotoVisibility,
                                                onLongPress: (id) =>
                                                    setState(() {
                                                  _selectMode = true;
                                                  _selectedPhotoIds.add(id);
                                                }),
                                                onTapInSelect: (id) =>
                                                    setState(() {
                                                  if (_selectedPhotoIds
                                                      .contains(id)) {
                                                    _selectedPhotoIds
                                                        .remove(id);
                                                    if (_selectedPhotoIds
                                                        .isEmpty) {
                                                      _selectMode = false;
                                                    }
                                                  } else {
                                                    _selectedPhotoIds.add(id);
                                                  }
                                                }),
                                              ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                  );
                                },
                              ),

                              // ── Friends section ─────────────────────────
                              _FriendsSection(
                                targetUserId: widget.targetUserId,
                                currentUserId: widget.currentUserId,
                                currentUserName: widget.currentUserName,
                                currentUserImage: widget.currentUserImage,
                                roomService: roomService,
                              ),

                              const SizedBox(height: 12),

                              // ── Rooms section ───────────────────────────
                              _RoomsSection(
                                targetUserId: widget.targetUserId,
                                isOwn: widget.isOwnProfile,
                                roomService: roomService,
                                onTapRoom: _openRoom,
                              ),

                              const SizedBox(height: 12),

                              // ── Stats section ───────────────────────────
                              _SectionCard(
                                icon: Icons.bar_chart_rounded,
                                title: 'الإحصائيات',
                                showSettings: true,
                                showMenu: true,
                                child: _StatsSection(
                                  isOwn: widget.isOwnProfile,
                                  isOnline: isOnline,
                                  onlineVisibility: onlineVis,
                                  joinedAt: joinedAt,
                                  joinDateVisibility: joinDateVis,
                                  usageHours: usageHours,
                                  usageVisibility: usageVis,
                                  chartVisibility: chartVis,
                                  canView: _canViewStat,
                                  onChangeOnlineVis: () async {
                                    final v =
                                        await _showPrivacySheet(context);
                                    if (v != null && mounted) {
                                      await roomService.updateUserProfile(
                                        uid: widget.targetUserId,
                                        onlineVisibility: v,
                                      );
                                    }
                                  },
                                  onChangeJoinDateVis: () async {
                                    final v =
                                        await _showPrivacySheet(context);
                                    if (v != null && mounted) {
                                      await roomService.updateUserProfile(
                                        uid: widget.targetUserId,
                                        joinDateVisibility: v,
                                      );
                                    }
                                  },
                                  onChangeUsageVis: () async {
                                    final v =
                                        await _showPrivacySheet(context);
                                    if (v != null && mounted) {
                                      await roomService.updateUserProfile(
                                        uid: widget.targetUserId,
                                        usageVisibility: v,
                                      );
                                    }
                                  },
                                  onChangeChartVis: () async {
                                    final v =
                                        await _showPrivacySheet(context);
                                    if (v != null && mounted) {
                                      await roomService.updateUserProfile(
                                        uid: widget.targetUserId,
                                        chartVisibility: v,
                                      );
                                    }
                                  },
                                ),
                              ),

                              // ── Add friend button (other profiles) ──────
                              if (!widget.isOwnProfile) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      await roomService.sendFriendRequest(
                                        fromUserId: widget.currentUserId,
                                        fromName: widget.currentUserName,
                                        fromImage: widget.currentUserImage,
                                        toUserId: widget.targetUserId,
                                        toName: name,
                                        toImage: photoUrl,
                                      );
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'تم إرسال طلب الصداقة')),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.person_add_rounded,
                                        size: 20),
                                    label: const Text('إضافة صديق'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF7B3FE4),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                    ),
                                  ),
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
          ],
        ),
      ),
    );
  }
}

// ─── Inline Text Field ────────────────────────────────────────────────────────
// Shared widget for inline editing of name and username in the profile header.

class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
    required this.value,
    required this.isEditing,
    required this.isSaving,
    required this.isOwn,
    required this.controller,
    required this.focusNode,
    required this.textStyle,
    required this.onTap,
    required this.onSubmit,
    this.textDirection = TextDirection.rtl,
    this.inputFormatters,
  });

  final String value;
  final bool isEditing;
  final bool isSaving;
  final bool isOwn;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle textStyle;
  final VoidCallback onTap;
  final VoidCallback onSubmit;
  final TextDirection textDirection;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
      );
    }
    if (isEditing && isOwn) {
      return IntrinsicWidth(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          textDirection: textDirection,
          inputFormatters: inputFormatters,
          style: textStyle,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onSubmitted: (_) => onSubmit(),
        ),
      );
    }
    if (value.isEmpty && !isOwn) return const SizedBox.shrink();
    return GestureDetector(
      onTap: isOwn ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            Text(value, style: textStyle),
          if (isOwn && value.isEmpty)
            Text(
              textDirection == TextDirection.ltr ? '@username' : 'اكتب اسمك',
              style: textStyle.copyWith(color: Colors.white30),
            ),
          if (isOwn) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, color: Colors.white30, size: 12),
          ],
        ],
      ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.photoUrl,
    required this.photoUrlVisibility,
    required this.isOnline,
    required this.isOwn,
    required this.country,
    required this.uploadingAvatar,
    required this.onPickAvatar,
    required this.onChangeAvatarVis,
    required this.nameWidget,
    required this.usernameWidget,
  });

  final String photoUrl;
  final String photoUrlVisibility;
  final bool isOnline;
  final bool isOwn;
  final String country;
  final ValueNotifier<bool> uploadingAvatar;
  final VoidCallback onPickAvatar;
  final VoidCallback onChangeAvatarVis;
  final Widget nameWidget;
  final Widget usernameWidget;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          // Avatar with overlay icons
          ValueListenableBuilder<bool>(
            valueListenable: uploadingAvatar,
            builder: (_, uploading, __) => Stack(
              clipBehavior: Clip.none,
              children: [
                // Glow ring
                Container(
                  width: 114,
                  height: 114,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF7B3FE4), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B3FE4).withOpacity(0.45),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: uploading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : CircleAvatar(
                          radius: 55,
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          backgroundColor: const Color(0xFF2D1F5E),
                          child: photoUrl.isEmpty
                              ? const Icon(Icons.person,
                                  size: 54, color: Colors.white54)
                              : null,
                        ),
                ),

                // Online / offline dot — bottom-left of avatar
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFF4CAF50)
                          : Colors.grey.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF17112F), width: 2.5),
                    ),
                  ),
                ),

                // Eye icon — top-left (owner only)
                if (isOwn)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: GestureDetector(
                      onTap: uploading ? null : onChangeAvatarVis,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17112F),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.2)),
                        ),
                        child: _EyeIconWidget(
                            visibility: photoUrlVisibility, size: 14),
                      ),
                    ),
                  ),

                // Camera — bottom-right (owner only)
                if (isOwn)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: uploading ? null : onPickAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Color(0xFF7B3FE4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Name (inline-editable for owner)
          nameWidget,

          const SizedBox(height: 4),

          // Username + country
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              usernameWidget,
              if (country.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(country,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Friends Section ──────────────────────────────────────────────────────────

class _FriendsSection extends StatefulWidget {
  const _FriendsSection({
    required this.targetUserId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.roomService,
  });

  final String targetUserId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final RoomService roomService;

  @override
  State<_FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends State<_FriendsSection> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.roomService.friendsStream(userId: widget.targetUserId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        Widget child;
        if (isLoading) {
          child = const SizedBox(
            height: 60,
            child: Center(
              child: CircularProgressIndicator(
                  color: Colors.white38, strokeWidth: 2),
            ),
          );
        } else if (docs.isEmpty) {
          child = const SizedBox(
            height: 60,
            child: Center(
              child: Text(
                'لا يوجد أصدقاء بعد',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          );
        } else {
          child = SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final d = docs[i].data();
                final uid = (d['userId'] ?? '').toString();
                final friendName = (d['name'] ?? '').toString();
                final image = (d['image'] ?? '').toString();
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        targetUserId: uid,
                        currentUserId: widget.currentUserId,
                        currentUserName: widget.currentUserName,
                        currentUserImage: widget.currentUserImage,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 56,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundImage: image.isNotEmpty
                              ? NetworkImage(image)
                              : null,
                          backgroundColor: const Color(0xFF2D1F5E),
                          child: image.isEmpty
                              ? const Icon(Icons.person,
                                  color: Colors.white54, size: 22)
                              : null,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          friendName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }

        return _SectionCard(
          icon: Icons.people_rounded,
          title: 'الأصدقاء (${docs.length})',
          showMenu: false,
          child: child,
        );
      },
    );
  }
}

// ─── Rooms Section ────────────────────────────────────────────────────────────

class _RoomsSection extends StatefulWidget {
  const _RoomsSection({
    required this.targetUserId,
    required this.isOwn,
    required this.roomService,
    required this.onTapRoom,
  });

  final String targetUserId;
  final bool isOwn;
  final RoomService roomService;
  final Future<void> Function(Map<String, dynamic> data, String roomId) onTapRoom;

  @override
  State<_RoomsSection> createState() => _RoomsSectionState();
}

class _RoomsSectionState extends State<_RoomsSection> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.roomService.profileRoomsStream(
      widget.targetUserId,
      isOwner: widget.isOwn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return _SectionCard(
          icon: Icons.mic_rounded,
          title: 'الغرف (${docs.length})',
          showMenu: false,
          child: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(
                        color: Colors.white38, strokeWidth: 2),
                  ),
                )
              : snapshot.hasError
                  ? const SizedBox(
                      height: 60,
                      child: Center(
                        child: Text(
                          'تعذّر تحميل الغرف',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                    )
                  : docs.isEmpty
                  ? const SizedBox(
                      height: 60,
                      child: Center(
                        child: Text(
                          'لا توجد غرف بعد',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                    )
                  : Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final roomId = doc.id;
                    final title = (data['title'] ?? 'غرفة').toString();
                    final image = (data['image'] ?? '').toString();
                    final isOpen = data['isOpen'] == true;
                    final members =
                        (data['usersCount'] as num?)?.toInt() ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => widget.onTapRoom(data, roomId),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Row(
                            children: [
                              // Room image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: image.isNotEmpty
                                    ? Image.network(image,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover)
                                    : Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2D1F5E),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                            Icons.mic_rounded,
                                            color: Colors.white38,
                                            size: 24),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Title + member count
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.people_outlined,
                                            color: Colors.white38, size: 13),
                                        const SizedBox(width: 4),
                                        Text('$members',
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Open / closed badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isOpen
                                      ? const Color(0xFF4CAF50)
                                          .withOpacity(0.15)
                                      : Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isOpen
                                        ? const Color(0xFF4CAF50)
                                            .withOpacity(0.4)
                                        : Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                child: Text(
                                  isOpen ? 'مفتوحة' : 'مغلقة',
                                  style: TextStyle(
                                    color: isOpen
                                        ? const Color(0xFF4CAF50)
                                        : Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.visibility,
    this.onVisibilityTap,
    this.showSettings = false,
    this.showMenu = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? visibility;
  final VoidCallback? onVisibilityTap;
  final bool showSettings;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (visibility != null)
                  GestureDetector(
                    onTap: onVisibilityTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child:
                          _EyeIconWidget(visibility: visibility!, size: 17),
                    ),
                  ),
                if (showSettings)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.settings_rounded,
                        color: Colors.white38, size: 17),
                  ),
                if (showMenu)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.more_vert_rounded,
                        color: Colors.white38, size: 17),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─── Bio Content ─────────────────────────────────────────────────────────────

class _BioContent extends StatelessWidget {
  const _BioContent({
    required this.bio,
    required this.isOwn,
    required this.canView,
    required this.editing,
    required this.saving,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onSave,
  });

  final String bio;
  final bool isOwn;
  final bool canView;
  final bool editing;
  final bool saving;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (!isOwn && !canView) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'لا توجد نبذة',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }
    if (!isOwn && bio.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'لا توجد نبذة',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: editing
                ? const Color(0xFF7B3FE4)
                : Colors.white.withOpacity(0.06),
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
                      color:
                          bio.isEmpty ? Colors.white30 : Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
      ),
    );
  }
}

// ─── Photos Grid ──────────────────────────────────────────────────────────────

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({
    required this.docs,
    required this.isOwn,
    required this.selectMode,
    required this.selectedIds,
    required this.onAddPhoto,
    required this.onEyeTap,
    required this.onLongPress,
    required this.onTapInSelect,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool isOwn;
  final bool selectMode;
  final Set<String> selectedIds;
  final VoidCallback onAddPhoto;
  final void Function(String id) onEyeTap;
  final void Function(String id) onLongPress;
  final void Function(String id) onTapInSelect;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty && !isOwn) return const SizedBox.shrink();

    final itemCount = isOwn ? docs.length + 1 : docs.length;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (isOwn && i == 0) {
          return GestureDetector(
            onTap: onAddPhoto,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF7B3FE4).withOpacity(0.3),
                    width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.add_photo_alternate_rounded,
                    color: Color(0xFF9B72F0), size: 28),
              ),
            ),
          );
        }

        final idx = isOwn ? i - 1 : i;
        final data = docs[idx].data();
        final url = (data['url'] as String?) ?? '';
        final vis = (data['visibility'] as String?) ?? 'public';
        final displayVis = vis == 'private' ? 'hidden' : vis;
        final id = docs[idx].id;
        final isSelected = selectedIds.contains(id);

        return GestureDetector(
          onLongPress: isOwn && !selectMode ? () => onLongPress(id) : null,
          onTap: (selectMode && isOwn) ? () => onTapInSelect(id) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: url.isNotEmpty
                    ? Image.network(url,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) => p == null
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
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
              ),
              if (isOwn && !selectMode)
                Positioned(
                  top: 5,
                  right: 5,
                  child: GestureDetector(
                    onTap: () => onEyeTap(id),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _EyeIconWidget(visibility: displayVis, size: 11),
                    ),
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
  }
}

// ─── Stats Section ────────────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection({
    required this.isOwn,
    required this.isOnline,
    required this.onlineVisibility,
    required this.joinedAt,
    required this.joinDateVisibility,
    required this.usageHours,
    required this.usageVisibility,
    required this.chartVisibility,
    required this.canView,
    required this.onChangeOnlineVis,
    required this.onChangeJoinDateVis,
    required this.onChangeUsageVis,
    required this.onChangeChartVis,
  });

  final bool isOwn;
  final bool isOnline;
  final String onlineVisibility;
  final Timestamp? joinedAt;
  final String joinDateVisibility;
  final int usageHours;
  final String usageVisibility;
  final String chartVisibility;
  final bool Function(String vis) canView;
  final VoidCallback onChangeOnlineVis;
  final VoidCallback onChangeJoinDateVis;
  final VoidCallback onChangeUsageVis;
  final VoidCallback onChangeChartVis;

  String _formatJoinDate(Timestamp ts) {
    final d = ts.toDate();
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${months[d.month - 1]} ${d.day}، ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isOwn || canView(onlineVisibility))
          _StatRow(
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isOnline
                    ? const Color(0xFF4CAF50)
                    : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            label: 'متصل',
            value: '',
            visibility: onlineVisibility,
            isOwn: isOwn,
            onVisibilityTap: onChangeOnlineVis,
          ),
        if (joinedAt != null && (isOwn || canView(joinDateVisibility))) ...[
          const SizedBox(height: 10),
          _StatRow(
            leading: const Icon(Icons.calendar_today_rounded,
                color: Colors.white54, size: 16),
            label: 'تاريخ الانضمام',
            value: _formatJoinDate(joinedAt!),
            visibility: joinDateVisibility,
            isOwn: isOwn,
            onVisibilityTap: onChangeJoinDateVis,
          ),
        ],
        if (isOwn || canView(usageVisibility)) ...[
          const SizedBox(height: 10),
          _StatRow(
            leading: const Icon(Icons.access_time_rounded,
                color: Colors.white54, size: 16),
            label: 'الاستخدام',
            value: '$usageHours ساعة',
            visibility: usageVisibility,
            isOwn: isOwn,
            onVisibilityTap: onChangeUsageVis,
          ),
        ],
        if (isOwn || canView(chartVisibility)) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 80,
                  child: CustomPaint(
                    painter: _ActivityChartPainter(usageHours: usageHours),
                  ),
                ),
              ),
              if (isOwn)
                Padding(
                  padding: const EdgeInsets.only(right: 4, left: 8),
                  child: GestureDetector(
                    onTap: onChangeChartVis,
                    child: _EyeIconWidget(
                        visibility: chartVisibility, size: 15),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.visibility,
    required this.isOwn,
    required this.onVisibilityTap,
  });

  final Widget leading;
  final String label;
  final String value;
  final String visibility;
  final bool isOwn;
  final VoidCallback onVisibilityTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        if (value.isNotEmpty)
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        if (isOwn) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onVisibilityTap,
            child: _EyeIconWidget(visibility: visibility, size: 15),
          ),
        ],
      ],
    );
  }
}

// ─── Eye Icon Widget ──────────────────────────────────────────────────────────

class _EyeIconWidget extends StatelessWidget {
  const _EyeIconWidget({required this.visibility, required this.size});

  final String visibility;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (visibility) {
      case 'friends':
        return Icon(Icons.people_rounded, color: Colors.white70, size: size);
      case 'hidden':
        return Icon(Icons.visibility_off_rounded,
            color: Colors.white54, size: size);
      default:
        return Icon(Icons.remove_red_eye_rounded,
            color: Colors.white, size: size);
    }
  }
}

// ─── Privacy Option ───────────────────────────────────────────────────────────

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Selection Bar ────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onPublic,
    required this.onFriends,
    required this.onHidden,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onDelete;
  final VoidCallback onPublic;
  final VoidCallback onFriends;
  final VoidCallback onHidden;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF1E1340).withOpacity(0.95),
      child: Row(
        children: [
          Text('$count مختار',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          _BarBtn(
              icon: Icons.remove_red_eye_rounded,
              label: 'عام',
              color: Colors.greenAccent,
              onTap: onPublic),
          _BarBtn(
              icon: Icons.people_rounded,
              label: 'أصدقاء',
              color: Colors.blueAccent,
              onTap: onFriends),
          _BarBtn(
              icon: Icons.visibility_off_rounded,
              label: 'مخفي',
              color: Colors.orangeAccent,
              onTap: onHidden),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 20),
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

class _BarBtn extends StatelessWidget {
  const _BarBtn({
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
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 13, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 11)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ─── Activity Chart Painter ───────────────────────────────────────────────────

class _ActivityChartPainter extends CustomPainter {
  _ActivityChartPainter({required this.usageHours});

  final int usageHours;

  @override
  void paint(Canvas canvas, Size size) {
    final barPaint = Paint()
      ..color = const Color(0xFF7B3FE4).withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final axisPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, size.height - 12),
        Offset(size.width, size.height - 12), axisPaint);

    final rng = math.Random(42);
    const barCount = 28;
    final barWidth = size.width / (barCount * 1.6);
    final gap = (size.width - barWidth * barCount) / (barCount + 1);
    final maxBarH = size.height - 20.0;

    for (int i = 0; i < barCount; i++) {
      final h = (rng.nextDouble() * 0.7 + (i % 7 == 0 ? 0.3 : 0))
              .clamp(0.05, 1.0) *
          maxBarH;
      final x = gap + i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 12 - h, barWidth, h),
          const Radius.circular(3),
        ),
        barPaint,
      );
    }

    final labelStyle = TextStyle(
        color: Colors.white.withOpacity(0.35), fontSize: 9);
    const years = ['2024', '2025', '2026'];
    for (int y = 0; y < years.length; y++) {
      final tp = TextPainter(
        text: TextSpan(text: years[y], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(size.width * (y / (years.length - 1)) - tp.width / 2,
              size.height - 10));
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityChartPainter old) => false;
}

// ─── Background Painter ───────────────────────────────────────────────────────

class _ProfileBgPainter extends CustomPainter {
  _ProfileBgPainter(this.value);

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
