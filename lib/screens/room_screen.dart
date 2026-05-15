import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/room.dart';
import '../services/room_service.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.room,
    required this.roomId,
  });

  final Room room;
  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final YoutubePlayerController youtubeController;
  final TextEditingController chatController = TextEditingController();
  final ScrollController chatScrollController = ScrollController();
  final RoomService roomService = RoomService();

  bool isMicOn = false;
  bool isRoomOwner = true;
  bool everyoneCanUseMic = false;
  late bool isPrivateRoom;

  final String currentUserName = 'Mohammed';
  final String activeSpeakerName = 'Fahad';

  final List<String> kickedUsers = [];

  List<RoomUser> users = [];

  @override
  void initState() {
    super.initState();
    isPrivateRoom = widget.room.isPrivate;

    youtubeController = YoutubePlayerController(
      initialVideoId: widget.room.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
      ),
    );
  }

  @override
  void dispose() {
    youtubeController.dispose();
    chatController.dispose();
    chatScrollController.dispose();
    super.dispose();
  }

  RoomUser get currentUser {
    return users.firstWhere(
      (user) => user.name == currentUserName,
      orElse: () => RoomUser(
        name: currentUserName,
        image: 'https://i.pravatar.cc/150?img=11',
        role: 'User',
        isSpeaker: false,
        hasMicPermission: false,
      ),
    );
  }

  bool get hasMicPermission {
    return currentUser.hasMicPermission || everyoneCanUseMic || isRoomOwner;
  }

  Future<void> confirmExitRoom() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leave room'),
          content: const Text('Are you sure you want to leave this room?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldExit == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> sendMessage() async {
    final text = chatController.text.trim();

    if (text.isEmpty) return;

    chatController.clear();

    await roomService.sendMessage(
      roomId: widget.roomId,
      userId: 'user_mohammed',
      name: currentUserName,
      image: currentUser.image,
      message: text,
      isLeader: currentUser.isLeader,
    );
  }

  void toggleMic() {
    if (!hasMicPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have mic permission')),
      );
      return;
    }

    setState(() {
      isMicOn = !isMicOn;
    });
  }

  void sendInvite() {
    final canInvite = !isPrivateRoom || isRoomOwner;

    if (!canInvite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the room owner can invite in private rooms'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite system opened')),
    );
  }

  void openRoomSettings() {
    if (!isRoomOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the room leader can open settings')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Room Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      value: everyoneCanUseMic,
                      activeColor: Colors.white,
                      title: const Text(
                        'Everyone can use mic',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Allow all users to turn on their mic',
                        style: TextStyle(color: Colors.white54),
                      ),
                      onChanged: (value) {
                        setState(() {
                          everyoneCanUseMic = value;
                        });
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      value: isPrivateRoom,
                      activeColor: Colors.white,
                      title: const Text(
                        'Private room',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Only invited users can enter',
                        style: TextStyle(color: Colors.white54),
                      ),
                      onChanged: (value) {
                        setState(() {
                          isPrivateRoom = value;
                        });
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void toggleUserMicPermission(RoomUser user) {
    if (!isRoomOwner) return;

    final newPermission = !user.hasMicPermission;

    roomService.updateMicPermission(
      roomId: widget.roomId,
      userId: user.userId,
      hasMicPermission: newPermission,
    );

    roomService.sendSystemMessage(
      roomId: widget.roomId,
      text: newPermission
          ? '${user.name} got the mic'
          : 'Mic removed from ${user.name}',
      userId: user.userId,
      name: user.name,
      image: user.image,
      isLeader: user.isLeader,
      icon: newPermission ? Icons.mic_rounded : Icons.mic_off_rounded,
    );
  }

  void kickUser(RoomUser user) {
    if (!isRoomOwner) return;

    roomService.kickUser(
      roomId: widget.roomId,
      userId: user.userId,
      name: user.name,
      image: user.image,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${user.name} can only rejoin by invitation')),
    );
  }

  void showRoomUsers() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'room-users',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 330,
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 90, 18, 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.34),
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: StreamBuilder(
                  stream: roomService.membersStream(widget.roomId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final roomUsers = docs
                        .map((doc) => roomUserFromFirestore(doc.data()))
                        .toList();

                    final isStillMember = roomUsers.any(
                      (user) => user.userId == currentUser.userId,
                    );

                    if (!isStillMember && mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You were removed from the room'),
                          ),
                        );

                        Navigator.pop(context);
                      });
                    }

                    if (roomUsers.isEmpty) {
                      return const Center(
                        child: Text(
                          'No users',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: roomUsers.length,
                      itemBuilder: (context, index) {
                        final user = roomUsers[index];

                        return RoomUserTile(
                          user: user,
                          isAdmin: isRoomOwner,
                          onToggleMicPermission: () {
                            toggleUserMicPermission(user);
                          },
                          onKick: () {
                            Navigator.pop(context);
                            kickUser(user);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        );
      },
    );
  }

  IconData micIcon() {
    if (!hasMicPermission) return Icons.mic_off_rounded;
    if (isMicOn) return Icons.mic_rounded;
    return Icons.mic_none_rounded;
  }

  Color micBackgroundColor() {
    if (!hasMicPermission) return Colors.white.withOpacity(0.55);
    if (isMicOn) return Colors.red;
    return Colors.white.withOpacity(0.92);
  }

  Color micIconColor() {
    if (!hasMicPermission) return Colors.black45;
    if (isMicOn) return Colors.white;
    return Colors.black;
  }

  ChatItem chatItemFromFirestore(Map<String, dynamic> data) {
    final type = data['type'] ?? 'message';

    if (type == 'system') {
      IconData? icon;

      if (data['iconCodePoint'] != null) {
        icon = IconData(
          data['iconCodePoint'],
          fontFamily: data['iconFontFamily'] ?? 'MaterialIcons',
        );
      }

      return ChatItem.system(
        text: data['text'] ?? '',
        icon: icon,
        customIcon: data['customIcon'],
        image: data['image'],
        isLeader: data['isLeader'] == true,
      );
    }

    return ChatItem.message(
      name: data['name'] ?? 'User',
      message: data['message'] ?? '',
      isLeader: data['isLeader'] == true,
    );
  }

  RoomUser roomUserFromFirestore(Map<String, dynamic> data) {
    return RoomUser(
      userId: data['userId'] ?? '',
      name: data['name'] ?? 'User',
      image: data['image'] ?? 'https://i.pravatar.cc/150',
      role: data['isLeader'] == true ? 'Owner' : 'Listener',
      isSpeaker: data['hasMicPermission'] == true,
      hasMicPermission: data['hasMicPermission'] == true,
      isLeader: data['isLeader'] == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSpeaker = users.isNotEmpty
        ? users.firstWhere(
            (user) => user.name == activeSpeakerName,
            orElse: () => users.first,
          )
        : currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder(
          stream: roomService.membersStream(widget.roomId),
          builder: (context, membersSnapshot) {
            final docs = membersSnapshot.data?.docs ?? [];

            users = docs
                .map((doc) => roomUserFromFirestore(doc.data()))
                .toList();

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF20114F),
                    Color(0xFF4B245B),
                    Color(0xFF102C6B),
                    Color(0xFF5A372D),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      height: 78,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: confirmExitRoom,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          IconButton(
                            onPressed: openRoomSettings,
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const Spacer(),
                          SpeakerAvatar(
                            user: activeSpeaker,
                            radius: 26,
                            isSpeaking:
                                isMicOn && activeSpeaker.name == currentUserName,
                            showName: false,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.search,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          IconButton(
                            onPressed: showRoomUsers,
                            icon: const Icon(
                              Icons.groups_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: YoutubePlayer(
                        controller: youtubeController,
                        showVideoProgressIndicator: true,
                        progressIndicatorColor: Colors.red,
                        progressColors: const ProgressBarColors(
                          playedColor: Colors.red,
                          handleColor: Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: StreamBuilder(
                          stream: roomService.messagesStream(widget.roomId),
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
                                ),
                              );
                            }

                            final docs = snapshot.data?.docs ?? [];

                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (chatScrollController.hasClients) {
                                chatScrollController.jumpTo(
                                  chatScrollController.position.maxScrollExtent,
                                );
                              }
                            });

                            if (docs.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No messages yet',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: chatScrollController,
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final data = docs[index].data();
                                final item = chatItemFromFirestore(data);

                                if (item.isSystem) {
                                  return SystemMessage(
                                    text: item.text,
                                    icon: item.icon,
                                    customIcon: item.customIcon,
                                    image: item.image,
                                    isLeader: item.isLeader,
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ChatBubble(
                                    name: item.name,
                                    message: item.message,
                                    isLeader: item.isLeader,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.28),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: toggleMic,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: micBackgroundColor(),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                micIcon(),
                                size: 38,
                                color: micIconColor(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: chatController,
                              onSubmitted: (_) => sendMessage(),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Chat',
                                hintStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 17,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.12),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: sendMessage,
                            icon: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 27,
                            ),
                          ),
                          IconButton(
                            onPressed: sendInvite,
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const Icon(
                            Icons.image,
                            color: Colors.white,
                            size: 27,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 72,
                      width: double.infinity,
                      color: Colors.black.withOpacity(0.22),
                      alignment: Alignment.center,
                      child: Container(
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Ad Space',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ChatItem {
  final bool isSystem;
  final String text;
  final IconData? icon;
  final String? customIcon;
  final String? image;
  final bool isLeader;
  final String name;
  final String message;

  const ChatItem._({
    required this.isSystem,
    this.text = '',
    this.icon,
    this.customIcon,
    this.image,
    this.isLeader = false,
    this.name = '',
    this.message = '',
  });

  factory ChatItem.system({
    required String text,
    IconData? icon,
    String? customIcon,
    String? image,
    bool isLeader = false,
  }) {
    return ChatItem._(
      isSystem: true,
      text: text,
      icon: icon,
      customIcon: customIcon,
      image: image,
      isLeader: isLeader,
    );
  }

  factory ChatItem.message({
    required String name,
    required String message,
    bool isLeader = false,
  }) {
    return ChatItem._(
      isSystem: false,
      name: name,
      message: message,
      isLeader: isLeader,
    );
  }
}

class RoomUser {
  final String userId;
  final String name;
  final String image;
  final String role;
  final bool isSpeaker;
  final bool isLeader;
  bool hasMicPermission;

  RoomUser({
    this.userId = '',
    required this.name,
    required this.image,
    required this.role,
    required this.isSpeaker,
    required this.hasMicPermission,
    this.isLeader = false,
  });
}

class CrownBadge extends StatelessWidget {
  const CrownBadge({
    super.key,
    this.size = 28,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.35,
      child: Icon(
        Icons.workspace_premium_rounded,
        color: Colors.white.withOpacity(0.95),
        size: size,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

class SpeakerAvatar extends StatefulWidget {
  const SpeakerAvatar({
    super.key,
    required this.user,
    required this.radius,
    required this.isSpeaking,
    this.showName = true,
  });

  final RoomUser user;
  final double radius;
  final bool isSpeaking;
  final bool showName;

  @override
  State<SpeakerAvatar> createState() => _SpeakerAvatarState();
}

class _SpeakerAvatarState extends State<SpeakerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> scaleAnimation;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    scaleAnimation = Tween<double>(
      begin: 1,
      end: 1.08,
    ).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );

    if (widget.isSpeaking) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SpeakerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isSpeaking && !controller.isAnimating) {
      controller.repeat(reverse: true);
    }

    if (!widget.isSpeaking && controller.isAnimating) {
      controller.stop();
      controller.reset();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.isSpeaking ? scaleAnimation.value : 1,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(widget.isSpeaking ? 4 : 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: widget.isSpeaking
                          ? [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.42),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                      border: Border.all(
                        color: widget.isSpeaking
                            ? Colors.white
                            : Colors.white.withOpacity(0.28),
                        width: widget.isSpeaking ? 3 : 1,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: widget.radius,
                      backgroundImage: NetworkImage(widget.user.image),
                    ),
                  ),
                  if (widget.user.isLeader)
                    Positioned(
                      top: -14,
                      left: -8,
                      child: CrownBadge(size: widget.radius * 0.95),
                    ),
                ],
              ),
            );
          },
        ),
        if (widget.showName) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: widget.radius * 2.4,
            child: Text(
              widget.user.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class RoomUserTile extends StatelessWidget {
  const RoomUserTile({
    super.key,
    required this.user,
    required this.isAdmin,
    required this.onToggleMicPermission,
    required this.onKick,
  });

  final RoomUser user;
  final bool isAdmin;
  final VoidCallback onToggleMicPermission;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: NetworkImage(user.image),
              ),
              if (user.isLeader)
                const Positioned(
                  top: -15,
                  left: -8,
                  child: CrownBadge(size: 25),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isAdmin) ...[
            IconButton(
              onPressed: onToggleMicPermission,
              icon: Icon(
                user.hasMicPermission
                    ? Icons.mic_none_rounded
                    : Icons.mic_off_rounded,
                color: user.hasMicPermission ? Colors.white : Colors.redAccent,
                size: 24,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: Colors.white,
              ),
              color: const Color(0xFF21153E),
              onSelected: (value) {
                if (value == 'kick') {
                  onKick();
                }
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem(
                    value: 'kick',
                    child: Text(
                      'Kick',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ];
              },
            ),
          ],
        ],
      ),
    );
  }
}

class SystemMessage extends StatelessWidget {
  const SystemMessage({
    super.key,
    required this.text,
    this.icon,
    this.customIcon,
    this.image,
    this.isLeader = false,
  });

  final String text;
  final IconData? icon;
  final String? customIcon;
  final String? image;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (image != null) ...[
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundImage: NetworkImage(image!),
                ),
                if (isLeader)
                  const Positioned(
                    top: -11,
                    left: -7,
                    child: CrownBadge(size: 17),
                  ),
              ],
            ),
            const SizedBox(width: 10),
          ],
          if (customIcon != null) ...[
            Text(
              customIcon!,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(
              icon,
              color: Colors.white54,
              size: 16,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.name,
    required this.message,
    this.isLeader = false,
  });

  final String name;
  final String message;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$name ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isLeader)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: CrownBadge(size: 15),
                ),
              ),
            const TextSpan(
              text: ': ',
              style: TextStyle(color: Colors.white),
            ),
            TextSpan(
              text: message,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}