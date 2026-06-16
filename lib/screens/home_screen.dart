import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/notification_service.dart';
import '../services/room_service.dart';
import '../utils/stream_utils.dart';
import '../widgets/room_card.dart';
import '../widgets/search_box.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'room_screen.dart';
import 'settings_screen.dart';
import 'source_picker_screen.dart';
import 'youtube_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final RoomService roomService = RoomService();
  final NotificationService notificationService = NotificationService();
  late final AnimationController backgroundController;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _publicRoomsStream;

  User? get firebaseUser => FirebaseAuth.instance.currentUser;

  String get currentUserId => firebaseUser?.uid ?? 'guest_user';

  String get currentUserName {
    final displayName = firebaseUser?.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = firebaseUser?.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'User';
  }

  String get currentUserImage {
    final photoUrl = firebaseUser?.photoURL?.trim();

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return photoUrl;
    }

    return 'https://i.pravatar.cc/150?u=$currentUserId';
  }

  @override
  void initState() {
    super.initState();

    backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    _publicRoomsStream = safeFirestoreStream(roomService.publicOpenRoomsStream());
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
      id: roomId,
      title: video.title,
      image: video.image,
      users: 1,
      speakers: 1,
      hasYoutube: true,
      videoId: 'jfKfPfyJRdk',
      isPrivate: false,
      ownerId: currentUserId,
      ownerName: currentUserName,
      ownerImage: currentUserImage,
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

  Room roomFromFirestore(Map<String, dynamic> data, {String id = ''}) {
    return Room(
      id: id,
      title: data['title'] ?? 'Untitled Room',
      image: data['image'] ?? 'https://picsum.photos/400/300',
      users: data['usersCount'] ?? data['users'] ?? 0,
      speakers: data['speakersCount'] ?? data['speakers'] ?? 0,
      hasYoutube: data['hasYoutube'] ?? true,
      videoId: data['videoId'] ?? 'jfKfPfyJRdk',
      isPrivate: data['isPrivate'] ?? false,
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? '',
      ownerImage: data['ownerImage'] ?? '',
    );
  }

  Future<bool> canShowRoom(String roomId) async {
    return roomService.canUserEnterRoom(
      roomId: roomId,
      userId: currentUserId,
    );
  }

  void openSideMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'side-menu',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: SideMenuPanel(
            roomService: roomService,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            currentUserImage: currentUserImage,
            onOpenProfile: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    targetUserId: currentUserId,
                    currentUserId: currentUserId,
                    currentUserName: currentUserName,
                    currentUserImage: currentUserImage,
                  ),
                ),
              );
            },
            onOpenFriends: () {
              Navigator.pop(context);
              openFriendsScreen();
            },
            onOpenSettings: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        );
      },
    );
  }

  void openFriendsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendsScreen(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserImage: currentUserImage,
        ),
      ),
    );
  }

  void openNotificationsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(userId: currentUserId),
      ),
    );
  }

  String flagFromCountryCode(String? countryCode) {
    if (countryCode == null || countryCode.trim().length != 2) {
      return '🌐';
    }

    final code = countryCode.trim().toUpperCase();
    final firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;

    if (firstLetter < 0x1F1E6 ||
        firstLetter > 0x1F1FF ||
        secondLetter < 0x1F1E6 ||
        secondLetter > 0x1F1FF) {
      return '🌐';
    }

    return String.fromCharCodes([firstLetter, secondLetter]);
  }

  void showRoomMembersPreview({
    required String roomId,
    required Room room,
  }) {
    final membersStream = safeFirestoreStream(roomService.membersStream(roomId));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: 420,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'الموجودين داخل الروم',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: StreamBuilder(
                      stream: membersStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error: ${snapshot.error}',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        final snapshotData = snapshot.data as dynamic;
                        final docs = snapshotData?.docs ?? [];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'لا يوجد أعضاء داخل الروم الآن',
                              style: TextStyle(color: Colors.white60),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final name =
                                (data['name'] ?? data['userName'] ?? 'User')
                                    .toString();
                            final image =
                                (data['image'] ?? data['userImage'] ?? '')
                                    .toString();
                            final countryCode =
                                (data['countryCode'] ?? data['country'] ?? '')
                                    .toString();
                            final isLeader = data['isLeader'] == true ||
                                (room.ownerId.isNotEmpty &&
                                    doc.id == room.ownerId);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: image.isNotEmpty
                                    ? NetworkImage(image)
                                    : null,
                                child: image.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    flagFromCountryCode(countryCode),
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isLeader)
                                    const Icon(
                                      Icons.workspace_premium_rounded,
                                      color: Color(0xFFFFD54F),
                                      size: 21,
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                isLeader ? 'Leader' : 'Member',
                                style: const TextStyle(color: Colors.white54),
                              ),
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
      },
    );
  }

  Widget buildRoomCardWithPreview({
    required String roomId,
    required Room room,
  }) {
    return GestureDetector(
      onLongPress: () {
        showRoomMembersPreview(
          roomId: roomId,
          room: room,
        );
      },
      child: RoomCard(
        room: room,
        roomId: roomId,
      ),
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
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;

            if (velocity > 350) {
              openSideMenu();
            }
          },
          child: AnimatedWaveHomeBackground(
            controller: backgroundController,
            child: SafeArea(
              child: Column(
                children: [
                  HomeHeader(
                    onOpenMenu: openSideMenu,
                    onOpenFriends: openFriendsScreen,
                    onOpenNotifications: openNotificationsScreen,
                    notificationService: notificationService,
                    roomService: roomService,
                    currentUserId: currentUserId,
                    currentUserImage: currentUserImage,
                    onOpenProfile: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          targetUserId: currentUserId,
                          currentUserId: currentUserId,
                          currentUserName: currentUserName,
                          currentUserImage: currentUserImage,
                        ),
                      ),
                    ),
                  ),
                  const SearchBox(),
                  InvitedRoomsSection(
                    roomService: roomService,
                    currentUserId: currentUserId,
                    roomFromFirestore: roomFromFirestore,
                    onPreviewRoom: showRoomMembersPreview,
                  ),
                  Expanded(
                    child: StreamBuilder(
                      stream: _publicRoomsStream,
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

                        final snapshotData = snapshot.data as dynamic;
                        final docs = snapshotData?.docs ?? [];

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
                            final data =
                                docs[docIndex].data() as Map<String, dynamic>;
                            if ((data['ownerId'] ?? '').toString().trim().isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final room = roomFromFirestore(data, id: roomId);

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

                                return buildRoomCardWithPreview(
                                  roomId: roomId,
                                  room: room,
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
      ),
    );
  }
}

class InvitedRoomsSection extends StatefulWidget {
  const InvitedRoomsSection({
    super.key,
    required this.roomService,
    required this.currentUserId,
    required this.roomFromFirestore,
    required this.onPreviewRoom,
  });

  final RoomService roomService;
  final String currentUserId;
  final Room Function(Map<String, dynamic> data, {String id}) roomFromFirestore;
  final void Function({
    required String roomId,
    required Room room,
  }) onPreviewRoom;

  @override
  State<InvitedRoomsSection> createState() => _InvitedRoomsSectionState();
}

class _InvitedRoomsSectionState extends State<InvitedRoomsSection> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _invitesStream;

  @override
  void initState() {
    super.initState();
    _invitesStream = safeFirestoreStream(widget.roomService.myInvitesStream(userId: widget.currentUserId));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _invitesStream,
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

        final snapshotData = snapshot.data as dynamic;
        final invites = snapshotData?.docs ?? [];

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
                final invite = inviteDoc.data() as Map<String, dynamic>;
                final roomId = invite['roomId']?.toString() ?? inviteDoc.id;

                return FutureBuilder(
                  future: widget.roomService.roomDocFuture(roomId: roomId),
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

                    final roomDoc = roomSnapshot.data as dynamic;

                    if (roomDoc == null || roomDoc.exists == false) {
                      return const SizedBox.shrink();
                    }

                    final roomData = roomDoc.data() as Map<String, dynamic>?;

                    if (roomData == null ||
                        roomData['isOpen'] != true ||
                        roomData['isRealRoom'] != true) {
                      return const SizedBox.shrink();
                    }

                    if ((roomData['ownerId'] ?? '').toString().trim().isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final room = widget.roomFromFirestore(roomData, id: roomId);

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
                        await widget.roomService.deleteInviteFromUser(
                          userId: widget.currentUserId,
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
                      child: GestureDetector(
                        onLongPress: () {
                          widget.onPreviewRoom(
                            roomId: roomId,
                            room: room,
                          );
                        },
                        child: RoomCard(
                          room: room,
                          roomId: roomId,
                        ),
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

class SideMenuPanel extends StatelessWidget {
  const SideMenuPanel({
    super.key,
    required this.roomService,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.onOpenProfile,
    required this.onOpenFriends,
    required this.onOpenSettings,
  });

  final RoomService roomService;
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFriends;
  final VoidCallback onOpenSettings;

  Future<void> _confirmSignOut(BuildContext context) async {
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
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF17112F).withOpacity(0.98),
          border: Border(
            left: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ),

                // Profile header — tap to open profile
                GestureDetector(
                  onTap: onOpenProfile,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF7B3FE4),
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundImage: currentUserImage.isNotEmpty
                                ? NetworkImage(currentUserImage)
                                : null,
                            backgroundColor: const Color(0xFF2D1F5E),
                            child: currentUserImage.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.white54, size: 28)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentUserName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'عرض الملف الشخصي',
                                style: TextStyle(
                                  color: Color(0xFF7B3FE4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left_rounded,
                            color: Colors.white30, size: 20),
                      ],
                    ),
                  ),
                ),

                // Menu items
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _MenuItem(
                        icon: Icons.people_alt_rounded,
                        label: 'الأصدقاء',
                        color: const Color(0xFF1E88E5),
                        onTap: onOpenFriends,
                      ),
                      const SizedBox(height: 10),
                      _MenuItem(
                        icon: Icons.settings_rounded,
                        label: 'الإعدادات',
                        color: Colors.white70,
                        onTap: onOpenSettings,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Logout button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _MenuItem(
                    icon: Icons.logout_rounded,
                    label: 'تسجيل الخروج',
                    color: Colors.redAccent,
                    onTap: () => _confirmSignOut(context),
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_left_rounded, color: color.withOpacity(0.5), size: 20),
          ],
        ),
      ),
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

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.onOpenMenu,
    required this.onOpenFriends,
    required this.onOpenNotifications,
    required this.notificationService,
    required this.currentUserId,
    required this.roomService,
    required this.currentUserImage,
    required this.onOpenProfile,
  });

  final VoidCallback onOpenMenu;
  final VoidCallback onOpenFriends;
  final VoidCallback onOpenNotifications;
  final NotificationService notificationService;
  final RoomService roomService;
  final String currentUserId;
  final String currentUserImage;
  final VoidCallback onOpenProfile;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  late final Stream<int> _unreadNotifStream;
  late final Stream<int> _unreadPmStream;

  @override
  void initState() {
    super.initState();
    _unreadNotifStream = safeFirestoreStream(widget.notificationService.unreadCountStream(widget.currentUserId));
    _unreadPmStream = safeFirestoreStream(widget.roomService.unreadPrivateMessagesCount(userId: widget.currentUserId));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 18, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onOpenMenu,
            onLongPress: widget.onOpenProfile,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: CircleAvatar(
                backgroundImage: widget.currentUserImage.isNotEmpty
                    ? NetworkImage(widget.currentUserImage)
                    : null,
                backgroundColor: const Color(0xFF2D1F5E),
                child: widget.currentUserImage.isEmpty
                    ? const Icon(Icons.person, color: Colors.white54, size: 22)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: widget.onOpenMenu,
            icon: const Icon(
              Icons.menu_rounded,
              size: 28,
              color: Colors.white70,
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
          StreamBuilder<int>(
            stream: _unreadNotifStream,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: widget.onOpenNotifications,
                    icon: const Icon(
                      Icons.notifications_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Friends icon with private message badge
          StreamBuilder<int>(
            stream: _unreadPmStream,
            builder: (context, snapshot) {
              final pmCount = snapshot.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: widget.onOpenFriends,
                    icon: const Icon(
                      Icons.people_alt_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  if (pmCount > 0)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.lightBlueAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          pmCount > 99 ? '99+' : '$pmCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
