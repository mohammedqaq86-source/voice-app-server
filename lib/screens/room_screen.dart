import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/room.dart';
import '../models/room_member_model.dart';
import '../services/room_service.dart';

class ReplyTarget {
  final String name;
  final String message;

  const ReplyTarget({
    required this.name,
    required this.message,
  });
}

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

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final YoutubePlayerController youtubeController;
  final TextEditingController chatController = TextEditingController();
  final ScrollController chatScrollController = ScrollController();
  final RoomService roomService = RoomService();
  late final AnimationController backgroundController;

  bool isMicOn = false;
  bool isRoomOwner = true;
  bool everyoneCanUseMic = false;
  late bool isPrivateRoom;

  final String currentUserId = 'user_mohammed';
  final String currentUserName = 'Mohammed';
  final String currentUserImage = 'https://i.pravatar.cc/150?img=11';

  List<RoomUser> users = [];
  ReplyTarget? replyTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isPrivateRoom = widget.room.isPrivate;

    backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

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
  backgroundController.dispose();
  youtubeController.dispose();
  chatController.dispose();
  chatScrollController.dispose();

  WidgetsBinding.instance.removeObserver(this);

  roomService.leaveRoom(
    roomId: widget.roomId,
    userId: currentUserId,
  );

  super.dispose();
}

  RoomUser get currentUser {
    return users.firstWhere(
      (user) => user.userId == currentUserId,
      orElse: () => RoomUser(
        userId: currentUserId,
        name: currentUserName,
        image: currentUserImage,
        role: 'Owner',
        isSpeaker: false,
        hasMicPermission: true,
        isMicOn: false,
        isLeader: true,
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
    await roomService.leaveRoom(
      roomId: widget.roomId,
      userId: currentUserId,
    );

    Navigator.pop(context);
  }
}
  

  void scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!chatScrollController.hasClients) return;

      chatScrollController.animateTo(
        chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> sendMessage() async {
    final text = chatController.text.trim();
    if (text.isEmpty) return;

    final mentions = RegExp(r'@([\w\u0600-\u06FF]+)')
        .allMatches(text)
        .map((match) => match.group(1) ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final currentReply = replyTarget;

    chatController.clear();

    setState(() {
      replyTarget = null;
    });

    await roomService.sendMessage(
      roomId: widget.roomId,
      userId: currentUserId,
      name: currentUserName,
      image: currentUser.image,
      message: text,
      isLeader: currentUser.isLeader,
      replyToName: currentReply?.name,
      replyToMessage: currentReply?.message,
      mentions: mentions,
    );
  }

  void setReplyTarget(String name, String message) {
    setState(() {
      replyTarget = ReplyTarget(
        name: name,
        message: message,
      );
    });
  }

  void showMentionUsers() {
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No users in room')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(user.image),
                ),
                title: Text(
                  user.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  final oldText = chatController.text;
                  final mentionText = '@${user.name} ';

                  chatController.text = oldText.isEmpty
                      ? mentionText
                      : '$oldText $mentionText';

                  chatController.selection = TextSelection.fromPosition(
                    TextPosition(offset: chatController.text.length),
                  );

                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> toggleMic() async {
    if (!hasMicPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have mic permission')),
      );
      return;
    }

    final newMicState = !isMicOn;

    setState(() {
      isMicOn = newMicState;
    });

    await roomService.updateMicState(
      roomId: widget.roomId,
      userId: currentUserId,
      isMicOn: newMicState,
    );
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

  Future<void> toggleUserMicPermission(RoomUser user) async {
    if (!isRoomOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the room owner can control mic')),
      );
      return;
    }

    if (user.userId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User id is missing')),
      );
      return;
    }

    final newPermission = !user.hasMicPermission;

    try {
      await roomService.updateMicPermission(
        roomId: widget.roomId,
        userId: user.userId,
        hasMicPermission: newPermission,
      );

      await roomService.sendSystemMessage(
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
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update mic: $e')),
      );
    }
  }

  void kickUser(RoomUser user) {
    if (!isRoomOwner || user.userId == currentUser.userId) return;

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
                        .map(
                          (doc) => roomUserFromFirestore(
                            doc.data(),
                            documentId: doc.id,
                          ),
                        )
                        .toList();

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
                          currentUserId: currentUser.userId,
                          onToggleMicPermission: () {
                            toggleUserMicPermission(user);
                          },
                          onKick: () {
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
      replyToName: data['replyToName'],
      replyToMessage: data['replyToMessage'],
      mentions: List<String>.from(data['mentions'] ?? const []),
    );
  }

  bool isMohammedLeaderName(String name) {
    final normalizedName = name.trim().toLowerCase();
    return normalizedName == 'mohammed' || normalizedName == 'محمد';
  }

  RoomUser roomUserFromFirestore(
    Map<String, dynamic> data, {
    String documentId = '',
  }) {
    final member = RoomMemberModel.fromMap({
      ...data,
      if ((data['userId'] ?? '').toString().trim().isEmpty)
        'userId': documentId,
    });

    final isLeaderUser =
        member.isLeader || isMohammedLeaderName(member.name);

    return RoomUser(
      userId: member.userId,
      name: member.name.isEmpty ? 'User' : member.name,
      image: member.image.isEmpty ? 'https://i.pravatar.cc/150' : member.image,
      role: isLeaderUser ? 'Owner' : 'Listener',
      isSpeaker: member.isMicOn,
      hasMicPermission: member.hasMicPermission || isLeaderUser,
      isMicOn: member.isMicOn,
      isLeader: isLeaderUser,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder(
          stream: roomService.membersStream(widget.roomId),
          builder: (context, membersSnapshot) {
            final docs = membersSnapshot.data?.docs ?? [];

            users = docs
                .map(
                  (doc) => roomUserFromFirestore(
                    doc.data(),
                    documentId: doc.id,
                  ),
                )
                .toList();

            final isStillMember = users.any(
              (user) => user.userId == currentUser.userId,
            );

            if (!isStillMember && users.isNotEmpty && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You were removed from the room'),
                  ),
                );

                Navigator.pop(context);
              });
            }

            final activeSpeaker = users.where((user) => user.isMicOn).isNotEmpty
                ? users.firstWhere((user) => user.isMicOn)
                : null;

            return AnimatedWaveRoomBackground(
              controller: backgroundController,
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
                          if (activeSpeaker != null)
                            SpeakerAvatar(
                              user: activeSpeaker,
                              radius: 22,
                              isSpeaking: true,
                              showName: false,
                            )
                          else
                            const SizedBox(width: 44),
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
                        child: ChatMessagesList(
                          key: ValueKey(widget.roomId),
                          roomId: widget.roomId,
                          roomService: roomService,
                          chatScrollController: chatScrollController,
                          onReply: setReplyTarget,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (replyTarget != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.white.withOpacity(0.65),
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Reply to ${replyTarget!.name}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          replyTarget!.message,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        replyTarget = null;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
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
                              IconButton(
                                onPressed: showMentionUsers,
                                icon: const Icon(
                                  Icons.alternate_email_rounded,
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
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


class ChatMessagesList extends StatefulWidget {
  const ChatMessagesList({
    super.key,
    required this.roomId,
    required this.roomService,
    required this.chatScrollController,
    required this.onReply,
  });

  final String roomId;
  final RoomService roomService;
  final ScrollController chatScrollController;
  final void Function(String name, String message) onReply;

  @override
  State<ChatMessagesList> createState() => _ChatMessagesListState();
}

class _ChatMessagesListState extends State<ChatMessagesList>
    with AutomaticKeepAliveClientMixin {
  late final Stream messagesStream;
  late final DateTime sessionStartedAt;

  int lastMessagesCount = 0;
  int unreadMessagesCount = 0;

  @override
  void initState() {
    super.initState();

    sessionStartedAt = DateTime.now();
    messagesStream = widget.roomService.messagesStream(widget.roomId);

    widget.chatScrollController.addListener(() {
      if (!mounted) return;

      if (isNearBottom && unreadMessagesCount > 0) {
        setState(() {
          unreadMessagesCount = 0;
        });
      }
    });
  }

  @override
  bool get wantKeepAlive => true;

  bool get isNearBottom {
    if (!widget.chatScrollController.hasClients) return false;

    final position = widget.chatScrollController.position;
    return position.maxScrollExtent - position.pixels <= 20;
  }

  bool isMessageFromCurrentSession(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];

    if (createdAt == null) {
      return true;
    }

    try {
      final DateTime messageTime = createdAt.toDate();
      return !messageTime.isBefore(sessionStartedAt);
    } catch (_) {
      return true;
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.chatScrollController.hasClients) return;

      final targetOffset =
          widget.chatScrollController.position.maxScrollExtent + 300;

      await widget.chatScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        if (!widget.chatScrollController.hasClients) return;

        widget.chatScrollController.jumpTo(
          widget.chatScrollController.position.maxScrollExtent,
        );
      });
    });
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
      replyToName: data['replyToName'],
      replyToMessage: data['replyToMessage'],
      mentions: List<String>.from(data['mentions'] ?? const []),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder(
      stream: messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
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

        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((doc) {
          final data = doc.data();
          return isMessageFromCurrentSession(data);
        }).toList();

        final int previousCount = lastMessagesCount;
        final bool hadMessagesBefore = previousCount > 0;
        final bool hasNewMessage = docs.length > previousCount;
        final int newMessagesAmount = docs.length - previousCount;

        if (hasNewMessage && hadMessagesBefore) {
          if (isNearBottom) {
            unreadMessagesCount = 0;
          } else {
            unreadMessagesCount += newMessagesAmount;
          }
        }

        lastMessagesCount = docs.length;

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No new messages yet',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return Stack(
          children: [
            ListView.builder(
              controller: widget.chatScrollController,
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
                  child: Dismissible(
                    key: ValueKey('${item.name}-${item.message}-$index'),
                    direction: DismissDirection.startToEnd,
                    dismissThresholds: const {
                      DismissDirection.startToEnd: 0.01,
                    },
                    movementDuration: const Duration(milliseconds: 80),
                    resizeDuration: null,
                    confirmDismiss: (_) async {
                      widget.onReply(item.name, item.message);
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.reply_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    child: ChatBubble(
                      name: item.name,
                      message: item.message,
                      isLeader: item.isLeader,
                      replyToName: item.replyToName,
                      replyToMessage: item.replyToMessage,
                      mentions: item.mentions,
                    ),
                  ),
                );
              },
            ),

            if (unreadMessagesCount > 0)
              Positioned(
                left: 12,
                bottom: 12,
                child: GestureDetector(
                  onTap: () {
                    scrollToBottom();

                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (!mounted) return;

                      setState(() {
                        unreadMessagesCount = 0;
                      });
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      '$unreadMessagesCount new messages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
  final String? replyToName;
  final String? replyToMessage;
  final List<String> mentions;

  const ChatItem._({
    required this.isSystem,
    this.text = '',
    this.icon,
    this.customIcon,
    this.image,
    this.isLeader = false,
    this.name = '',
    this.message = '',
    this.replyToName,
    this.replyToMessage,
    this.mentions = const [],
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
    String? replyToName,
    String? replyToMessage,
    List<String> mentions = const [],
  }) {
    return ChatItem._(
      isSystem: false,
      name: name,
      message: message,
      isLeader: isLeader,
      replyToName: replyToName,
      replyToMessage: replyToMessage,
      mentions: mentions,
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
  final bool isMicOn;
  bool hasMicPermission;

  RoomUser({
    this.userId = '',
    required this.name,
    required this.image,
    required this.role,
    required this.isSpeaker,
    required this.hasMicPermission,
    required this.isMicOn,
    this.isLeader = false,
  });
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
    final bool isLeaderUser =
        widget.user.isLeader || widget.user.role.toLowerCase() == 'owner';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.isSpeaking ? scaleAnimation.value : 1,
              child: LeaderGoldAvatar(
                image: widget.user.image,
                radius: widget.radius,
                isLeader: isLeaderUser,
                isSpeaking: widget.isSpeaking,
                crownSize: widget.radius * 0.62,
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


class LeaderGoldAvatar extends StatelessWidget {
  const LeaderGoldAvatar({
    super.key,
    required this.image,
    required this.radius,
    required this.isLeader,
    this.isSpeaking = false,
    this.crownSize,
  });

  final String image;
  final double radius;
  final bool isLeader;
  final bool isSpeaking;
  final double? crownSize;

  @override
  Widget build(BuildContext context) {
    final double effectiveCrownSize = crownSize ?? radius * 0.82;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSpeaking
                  ? Colors.white
                  : Colors.white.withOpacity(0.20),
              width: isSpeaking ? 2.2 : 1,
            ),
            boxShadow: isSpeaking
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.34),
                      blurRadius: 14,
                      spreadRadius: 1.4,
                    ),
                  ]
                : [],
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundImage: NetworkImage(image),
          ),
        ),


        // تاج VIP أفخم، ثابت فوق الإطار ومربوط فيه.
        if (isLeader)
          Positioned(
            top: -(effectiveCrownSize * 1.04),
            child: CustomPaint(
              size: Size(effectiveCrownSize * 1.85, effectiveCrownSize * 1.08),
              painter: PremiumGoldCrownPainter(),
            ),
          ),
      ],
    );
  }
}

class PremiumGoldCrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Path crown = Path()
      ..moveTo(size.width * 0.07, size.height * 0.76)
      ..lineTo(size.width * 0.14, size.height * 0.26)
      ..lineTo(size.width * 0.31, size.height * 0.54)
      ..lineTo(size.width * 0.42, size.height * 0.13)
      ..lineTo(size.width * 0.50, size.height * 0.48)
      ..lineTo(size.width * 0.58, size.height * 0.13)
      ..lineTo(size.width * 0.69, size.height * 0.54)
      ..lineTo(size.width * 0.86, size.height * 0.26)
      ..lineTo(size.width * 0.93, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.94,
        size.width * 0.07,
        size.height * 0.76,
      )
      ..close();

    final Paint shadow = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(crown.shift(const Offset(0, 2.5)), shadow);

    final Paint gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFBE0),
          Color(0xFFFFE082),
          Color(0xFFFFB300),
          Color(0xFFFF8F00),
        ],
        stops: [0.0, 0.35, 0.72, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(crown, gold);

    final Paint darkEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.black.withOpacity(0.45);
    canvas.drawPath(crown, darkEdge);

    final Paint highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withOpacity(0.62);
    canvas.drawPath(crown.shift(const Offset(0, -0.8)), highlight);

    final Paint baseLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFFF8C6),
          Color(0xFFFFB300),
          Color(0xFFFFF8C6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final Path base = Path()
      ..moveTo(size.width * 0.16, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.84,
        size.width * 0.84,
        size.height * 0.75,
      );
    canvas.drawPath(base, baseLine);

    void drawGem(double x, double y, double r, Color color) {
      final Paint gemShadow = Paint()
        ..color = Colors.black.withOpacity(0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(size.width * x, size.height * y + 1), r, gemShadow);

      final Paint gem = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.95),
            color,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * x, size.height * y),
            radius: r,
          ),
        );
      canvas.drawCircle(Offset(size.width * x, size.height * y), r, gem);
    }

    drawGem(0.50, 0.43, size.width * 0.047, const Color(0xFFFFF176));
    drawGem(0.22, 0.53, size.width * 0.032, const Color(0xFFFFE082));
    drawGem(0.78, 0.53, size.width * 0.032, const Color(0xFFFFE082));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnimatedWaveRoomBackground extends StatelessWidget {
  const AnimatedWaveRoomBackground({
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
          painter: RoomWaveBackgroundPainter(controller.value),
          child: child,
        );
      },
    );
  }
}

class RoomWaveBackgroundPainter extends CustomPainter {
  RoomWaveBackgroundPainter(this.value);

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
      baseY: size.height * 0.30,
      amplitude: 24,
      color: const Color(0xFF7B3FE4).withOpacity(0.20),
      height: size.height * 0.34,
    );

    _drawWave(
      canvas,
      size,
      phase: value * math.pi * 2 + 1.7,
      baseY: size.height * 0.56,
      amplitude: 30,
      color: const Color(0xFF1E88E5).withOpacity(0.16),
      height: size.height * 0.34,
    );

    _drawWave(
      canvas,
      size,
      phase: value * math.pi * 2 + 3.0,
      baseY: size.height * 0.76,
      amplitude: 22,
      color: const Color(0xFFFFA000).withOpacity(0.10),
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
  bool shouldRepaint(covariant RoomWaveBackgroundPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

class RoomUserTile extends StatelessWidget {
  const RoomUserTile({
    super.key,
    required this.user,
    required this.isAdmin,
    required this.currentUserId,
    required this.onToggleMicPermission,
    required this.onKick,
  });

  final RoomUser user;
  final bool isAdmin;
  final String currentUserId;
  final VoidCallback onToggleMicPermission;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final isLeaderUser = user.isLeader || user.role.toLowerCase() == 'owner';
    final canManageUser =
        isAdmin && user.userId.trim().isNotEmpty && user.userId != currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          LeaderGoldAvatar(
            image: user.image,
            radius: 26,
            isLeader: isLeaderUser,
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
          if (canManageUser) ...[
            IconButton(
              onPressed: onToggleMicPermission,
              icon: Icon(
                user.hasMicPermission
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                color: user.hasMicPermission ? Colors.greenAccent : Colors.redAccent,
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
            LeaderGoldAvatar(
              image: image!,
              radius: 11,
              isLeader: isLeader,
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
    this.replyToName,
    this.replyToMessage,
    this.mentions = const [],
  });

  final String name;
  final String message;
  final bool isLeader;
  final String? replyToName;
  final String? replyToMessage;
  final List<String> mentions;

  List<TextSpan> messageSpans() {
    if (mentions.isEmpty) {
      return [
        TextSpan(
          text: message,
          style: const TextStyle(color: Colors.white70),
        ),
      ];
    }

    final spans = <TextSpan>[];
    final mentionSet = mentions.map((name) => '@$name').toSet();

    final parts = message.split(' ');

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final textPart = i == parts.length - 1 ? part : '$part ';

      final cleanPart = part.trim();

      if (mentionSet.contains(cleanPart)) {
        spans.add(
          TextSpan(
            text: textPart,
            style: const TextStyle(
              color: Color(0xFF7DD3FC),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: textPart,
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = (replyToName ?? '').trim().isNotEmpty &&
        (replyToMessage ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReply) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withOpacity(0.55),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    replyToName!,
                    style: const TextStyle(
                      color: Color(0xFF7DD3FC),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    replyToMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$name ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(
                  text: ': ',
                  style: TextStyle(color: Colors.white),
                ),
                ...messageSpans(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

