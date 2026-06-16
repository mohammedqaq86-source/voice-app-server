import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/room.dart';
import '../models/room_member_model.dart';
import '../services/ad_service.dart';
import '../services/room_service.dart';
import '../utils/stream_utils.dart';
import '../utils/web_unload.dart';
import 'private_chat_screen.dart';

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

  static const String liveKitUrl = 'wss://mohammed-54ar6zrx.livekit.cloud';
  static const String liveKitTokenEndpoint =
      'https://voice-app-server-ssrz.onrender.com/token';

  final livekit.Room liveKitRoom = livekit.Room();
  final AdService _adService = AdService();
  Timer? speakingMonitorTimer;
  Timer? _heartbeatTimer;
  Timer? _pauseLeaveTimer;
  int _heartbeatTick = 0;
  Set<String> speakingUserIds = <String>{};

  // ── Banner ad ────────────────────────────────────────────────────────────
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  bool isVoiceConnected = false;
  bool isConnectingVoice = false;
  bool needsAudioPlaybackTap = false;

  bool isMicOn = false;
  bool hasJoinedRoom = false;
  bool isLeavingRoom = false;
  bool hasHandledRoomRemoval = false;
  bool _confirmedMembership = false;
  bool everyoneCanUseMic = false;
  bool _showUsersPanel = false;

  bool _lastKnownMicPermission = false;
  bool _micPermissionInitialized = false;
  late bool isPrivateRoom;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _membersPanelStream;
  StreamSubscription<dynamic>? roomSubscription;
  String currentOwnerId = '';
  String currentOwnerName = '';
  String currentOwnerImage = '';

  User? get firebaseUser => FirebaseAuth.instance.currentUser;

  String get currentUserId => firebaseUser?.uid ?? 'guest_user';

  String get currentUserName {
    final user = firebaseUser;
    final displayName = user?.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();

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

  bool get isRoomOwner {
    final ownerId = currentOwnerId.trim();
    return ownerId.isNotEmpty && ownerId == currentUserId;
  }

  bool get canManageRoom {
    return isRoomOwner || currentUser.isLeader;
  }

  List<RoomUser> users = [];
  ReplyTarget? replyTarget;


  void _loadBannerAd() {
    if (kIsWeb) return;
    _bannerAd = BannerAd(
      adUnitId: AdService.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!hasJoinedRoom || isLeavingRoom || currentUserId == 'guest_user') {
        return;
      }
      _heartbeatTick++;
      unawaited(roomService.updateMemberHeartbeat(
        roomId: widget.roomId,
        userId: currentUserId,
      ));
      // Every 3rd tick (~75 s) clean up any ghost members from this room.
      if (_heartbeatTick % 3 == 0) {
        unawaited(roomService.cleanupStaleMembers(
          roomId: widget.roomId,
          excludeUserId: currentUserId,
        ));
      }
    });
  }

  Future<void> ensureCurrentUserIsMember() async {
    final userId = currentUserId.trim();

    if (userId.isEmpty || userId == 'guest_user') return;

    try {
      await roomService.joinRoom(
        roomId: widget.roomId,
        userId: userId,
        name: currentUserName,
        image: currentUserImage,
        isLeader: isRoomOwner,
        hasMicPermission: isRoomOwner,
      );

      hasJoinedRoom = true;
      _startHeartbeat();
      _adService.loadInterstitial(); // preload so it's ready when user exits
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join room: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isPrivateRoom = widget.room.isPrivate;
    currentOwnerId = widget.room.ownerId;
    currentOwnerName = widget.room.ownerName;
    currentOwnerImage = widget.room.ownerImage;
    _membersPanelStream = safeFirestoreStream(roomService.membersStream(widget.roomId));

    roomSubscription = roomService.roomStream(widget.roomId).listen((snapshot) {
      final data = snapshot.data();
      if (!mounted || data == null) return;

      final nextOwnerId = (data['ownerId'] ?? '').toString();
      final nextOwnerName = (data['ownerName'] ?? '').toString();
      final nextOwnerImage = (data['ownerImage'] ?? '').toString();
      final nextPrivate = data['isPrivate'] == true;
      final nextAllMic = data['allMicEnabled'] == true;

      setState(() {
        currentOwnerId = nextOwnerId;
        currentOwnerName = nextOwnerName;
        currentOwnerImage = nextOwnerImage;
        isPrivateRoom = nextPrivate;
        everyoneCanUseMic = nextAllMic;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureCurrentUserIsMember();
      if (!mounted) return;
      unawaited(connectVoiceRoom());
    });

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

    _loadBannerAd();

    listenForPageUnload(() {
      if (!isLeavingRoom && hasJoinedRoom && currentUserId != 'guest_user') {
        isLeavingRoom = true;
        _heartbeatTimer?.cancel();
        unawaited(roomService.leaveRoom(
          roomId: widget.roomId,
          userId: currentUserId,
        ));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pauseLeaveTimer?.cancel();
      _pauseLeaveTimer = null;
      // Restart heartbeat so lastSeen stays fresh after returning from background.
      if (hasJoinedRoom && !isLeavingRoom && currentUserId != 'guest_user') {
        _startHeartbeat();
        unawaited(roomService.updateMemberHeartbeat(
          roomId: widget.roomId,
          userId: currentUserId,
        ));
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to background. Stop heartbeat and schedule a leave after 2 min
      // so that if the user never returns, the room member count stays accurate.
      _heartbeatTimer?.cancel();
      if (!isLeavingRoom && currentUserId != 'guest_user' && hasJoinedRoom) {
        _pauseLeaveTimer?.cancel();
        _pauseLeaveTimer = Timer(const Duration(minutes: 2), () {
          if (isLeavingRoom) return;
          isLeavingRoom = true;
          unawaited(disconnectVoiceRoom());
          unawaited(roomService.leaveRoom(
            roomId: widget.roomId,
            userId: currentUserId,
          ));
        });
      }
    } else if (state == AppLifecycleState.detached) {
      _pauseLeaveTimer?.cancel();
      _heartbeatTimer?.cancel();
      if (!isLeavingRoom && currentUserId != 'guest_user' && hasJoinedRoom) {
        isLeavingRoom = true;
        unawaited(disconnectVoiceRoom());
        unawaited(roomService.leaveRoom(
          roomId: widget.roomId,
          userId: currentUserId,
        ));
      }
    }
  }

  @override
  void dispose() {
    backgroundController.dispose();
    youtubeController.dispose();
    chatController.dispose();
    chatScrollController.dispose();

    WidgetsBinding.instance.removeObserver(this);

    roomSubscription?.cancel();
    speakingMonitorTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pauseLeaveTimer?.cancel();
    _bannerAd?.dispose();
    _adService.dispose();
    liveKitRoom.disconnect();

    if (!isLeavingRoom && currentUserId != 'guest_user') {
      unawaited(roomService.leaveRoom(
        roomId: widget.roomId,
        userId: currentUserId,
      ));
    }

    super.dispose();
  }

  RoomUser get currentUser {
    return users.firstWhere(
      (user) => user.userId == currentUserId,
      orElse: () => RoomUser(
        userId: currentUserId,
        name: currentUserName,
        image: currentUserImage,
        role: isRoomOwner ? 'Owner' : 'Listener',
        countryFlag: '🇸🇦',
        isSpeaker: false,
        hasMicPermission: isRoomOwner,
        isMicOn: false,
        isLeader: isRoomOwner,
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

    if (shouldExit != true || !mounted) return;

    // Capture mic state before any teardown.
    final wasUsingMic = isMicOn;

    isLeavingRoom = true;

    // Always stop voice first so the ad shows in silence.
    await disconnectVoiceRoom();

    Future<void> leaveAndPop() async {
      await roomService.leaveRoom(
        roomId: widget.roomId,
        userId: currentUserId,
      );
      if (mounted) Navigator.pop(context);
    }

    // Skip the interstitial if the user was actively speaking —
    // interrupting a voice session with an ad would be disruptive.
    if (!wasUsingMic && _adService.isInterstitialReady) {
      await _adService.showInterstitialAndThen(() => unawaited(leaveAndPop()));
    } else {
      await leaveAndPop();
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

  Future<String> getLiveKitToken() async {
    final response = await http.post(
      Uri.parse(liveKitTokenEndpoint),
      headers: const {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'roomId': widget.roomId,
        'userId': currentUserId,
        'userName': currentUserName,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Token server error: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('Token is empty');
    }

    return token;
  }

  Future<void> connectVoiceRoom() async {
    if (isVoiceConnected || isConnectingVoice) return;

    setState(() {
      isConnectingVoice = true;
    });

    try {
      final token = await getLiveKitToken();

      await liveKitRoom.connect(
        liveKitUrl,
        token,
      );

      await liveKitRoom.localParticipant?.setMicrophoneEnabled(false);
      await startAudioPlayback();

      if (!mounted) return;

      setState(() {
        isVoiceConnected = true;
        isConnectingVoice = false;
      });

      startSpeakingMonitor();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isVoiceConnected = false;
        isConnectingVoice = false;
        speakingUserIds = <String>{};
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect voice: $e')),
      );
    }
  }

  Future<void> startAudioPlayback() async {
    try {
      await liveKitRoom.startAudio();

      if (!mounted) return;

      setState(() {
        needsAudioPlaybackTap = !liveKitRoom.canPlaybackAudio;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        needsAudioPlaybackTap = true;
      });
    }
  }

  void startSpeakingMonitor() {
    speakingMonitorTimer?.cancel();

    speakingMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) {
        if (!mounted || !isVoiceConnected) return;

        final activeSpeakerIds = liveKitRoom.activeSpeakers
            .map((participant) => participant.identity)
            .whereType<String>()
            .toSet();

        if (setEquals(activeSpeakerIds, speakingUserIds)) return;

        setState(() {
          speakingUserIds = activeSpeakerIds;
        });
      },
    );
  }

  void stopSpeakingMonitor() {
    speakingMonitorTimer?.cancel();
    speakingMonitorTimer = null;

    if (!mounted) return;

    setState(() {
      speakingUserIds = <String>{};
    });
  }

  Future<void> disconnectVoiceRoom() async {
    stopSpeakingMonitor();

    try {
      await liveKitRoom.localParticipant?.setMicrophoneEnabled(false);
      await liveKitRoom.disconnect();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      isVoiceConnected = false;
      isMicOn = false;
      needsAudioPlaybackTap = false;
    });
  }

  Future<void> toggleMic() async {
    if (!hasMicPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الميكروفون')),
      );
      return;
    }

    final previousMicState = isMicOn;
    final newMicState = !isMicOn;

    if (newMicState && !kIsWeb) {
      final micPermission = await Permission.microphone.request();

      if (!micPermission.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')),
        );
        return;
      }
    }

    // Optimistic update — UI responds immediately
    setState(() {
      isMicOn = newMicState;
    });
    unawaited(roomService.updateMicState(
      roomId: widget.roomId,
      userId: currentUserId,
      isMicOn: newMicState,
    ));

    await connectVoiceRoom();

    if (!isVoiceConnected) {
      if (!mounted) return;
      setState(() {
        isMicOn = previousMicState;
      });
      unawaited(roomService.updateMicState(
        roomId: widget.roomId,
        userId: currentUserId,
        isMicOn: previousMicState,
      ));
      return;
    }

    await startAudioPlayback();

    try {
      await liveKitRoom.localParticipant?.setMicrophoneEnabled(newMicState);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isMicOn = previousMicState;
      });
      unawaited(roomService.updateMicState(
        roomId: widget.roomId,
        userId: currentUserId,
        isMicOn: previousMicState,
      ));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تشغيل الميكروفون: $e')),
      );
    }
  }

  void sendInvite() {
    _showInviteFriendsSheet();
  }

  void _showInviteFriendsSheet() {
    final friendsStream = safeFirestoreStream(roomService.friendsStream(userId: currentUserId));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            builder: (_, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 14),
                  Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 26),
                        SizedBox(width: 10),
                        Text(
                          'دعوة أصدقاء للروم',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder(
                      stream: friendsStream,
                      builder: (context, snapshot) {
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'لا يوجد أصدقاء لدعوتهم',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            final friendId = docs[index].id;
                            final friendName = (data['name'] ?? 'User').toString();
                            final friendImage = (data['image'] ?? '').toString();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: friendImage.isNotEmpty ? NetworkImage(friendImage) : null,
                                  child: friendImage.isEmpty ? const Icon(Icons.person) : null,
                                ),
                                title: Text(
                                  friendName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    try {
                                      await roomService.inviteUserToRoom(
                                        roomId: widget.roomId,
                                        roomTitle: widget.room.title,
                                        roomImage: widget.room.image,
                                        ownerId: currentUserId,
                                        ownerName: currentUserName,
                                        invitedUserId: friendId,
                                        invitedUserName: friendName,
                                        invitedUserImage: friendImage,
                                      );
                                      unawaited(roomService.sendNotification(
                                        toUserId: friendId,
                                        type: 'roomInvite',
                                        title: 'دعوة للانضمام إلى روم',
                                        body: '$currentUserName يدعوك للانضمام إلى ${widget.room.title}',
                                        fromUserId: currentUserId,
                                        fromName: currentUserName,
                                        fromImage: currentUserImage,
                                        roomId: widget.roomId,
                                        roomTitle: widget.room.title,
                                      ));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تم إرسال الدعوة إلى $friendName')),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('فشل إرسال الدعوة: $e')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.send_rounded, size: 16),
                                  label: const Text('دعوة'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.15),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void showFriendsList() {
    _showInviteFriendsSheet();
  }

  void showRoomMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
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
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'قائمة الأصدقاء',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showFriendsList();
                  },
                ),
                if (canManageRoom)
                  ListTile(
                    leading: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                    ),
                    title: const Text(
                      'إعدادات الروم',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      openRoomSettings();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> makeUserLeader(RoomUser user) async {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the room owner can assign leaders')),
      );
      return;
    }
    if (user.userId == currentUserId) return;

    try {
      await roomService.transferRoomLeadership(
        roomId: widget.roomId,
        oldOwnerId: currentUserId,
        newOwnerId: user.userId,
        newOwnerName: user.name,
        newOwnerImage: user.image,
      );

      unawaited(roomService.sendNotification(
        toUserId: user.userId,
        type: 'leaderTransferred',
        title: 'أنت الليدر الجديد 👑',
        body: '$currentUserName نقل إليك قيادة الروم',
        fromUserId: currentUserId,
        fromName: currentUserName,
        fromImage: currentUserImage,
        roomId: widget.roomId,
      ));

      if (!mounted) return;
      setState(() {
        currentOwnerId = user.userId;
        currentOwnerName = user.name;
        currentOwnerImage = user.image;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} أصبح ليدر الروم')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل نقل القيادة: $e')),
      );
    }
  }

  void openRoomSettings() {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فقط الليدر يمكنه فتح الإعدادات')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
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
                      'إعدادات الروم',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      value: isPrivateRoom,
                      activeColor: Colors.white,
                      title: const Text(
                        'روم خاص',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'فقط المدعوون يمكنهم الدخول',
                        style: TextStyle(color: Colors.white54),
                      ),
                      onChanged: (value) {
                        setSheetState(() {});
                        setState(() => isPrivateRoom = value);
                        unawaited(roomService.updateRoomPrivacy(
                          roomId: widget.roomId,
                          isPrivate: value,
                        ));
                      },
                    ),
                    SwitchListTile(
                      value: everyoneCanUseMic,
                      activeColor: Colors.white,
                      title: const Text(
                        'السماح للجميع بالمايك',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'يسمح لجميع الأعضاء بتشغيل المايك',
                        style: TextStyle(color: Colors.white54),
                      ),
                      onChanged: (value) {
                        setSheetState(() {});
                        if (value) {
                          unawaited(roomService.enableMicForAll(roomId: widget.roomId));
                        } else {
                          unawaited(roomService.disableMicForAll(roomId: widget.roomId));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await roomService.enableMicForAll(roomId: widget.roomId);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تفعيل المايك للجميع')),
                              );
                            },
                            icon: const Icon(Icons.mic_rounded, color: Colors.greenAccent),
                            label: const Text('تفعيل المايك للكل', style: TextStyle(color: Colors.greenAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await roomService.disableMicForAll(roomId: widget.roomId);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تعطيل المايك للجميع')),
                              );
                            },
                            icon: const Icon(Icons.mic_off_rounded, color: Colors.redAccent),
                            label: const Text('تعطيل المايك للكل', style: TextStyle(color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
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
    if (!canManageRoom) {
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

    setState(() {
      users = users.map((item) {
        if (item.userId != user.userId) return item;

        return item.copyWith(
          hasMicPermission: newPermission,
          isMicOn: newPermission ? item.isMicOn : false,
        );
      }).toList();
    });

    try {
      await roomService.updateMicPermission(
        roomId: widget.roomId,
        userId: user.userId,
        hasMicPermission: newPermission,
      );

      unawaited(roomService.sendSystemMessage(
        roomId: widget.roomId,
        text: newPermission
            ? '${user.name} حصل على الميكروفون'
            : 'تم سحب الميكروفون من ${user.name}',
        userId: user.userId,
        name: user.name,
        image: user.image,
        isLeader: user.isLeader,
        icon: newPermission ? Icons.mic_rounded : Icons.mic_off_rounded,
      ));

      unawaited(roomService.sendNotification(
        toUserId: user.userId,
        type: newPermission ? 'micGranted' : 'micRevoked',
        title: newPermission ? 'تم منحك الميكروفون 🎙️' : 'تم سحب الميكروفون',
        body: newPermission
            ? '$currentUserName منحك صلاحية استخدام الميكروفون'
            : '$currentUserName سحب صلاحية الميكروفون منك',
        fromUserId: currentUserId,
        fromName: currentUserName,
        fromImage: currentUserImage,
        roomId: widget.roomId,
      ));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        users = users.map((item) {
          if (item.userId != user.userId) return item;

          return item.copyWith(
            hasMicPermission: user.hasMicPermission,
            isMicOn: user.isMicOn,
          );
        }).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update mic: $e')),
      );
    }
  }

  Future<void> kickUser(RoomUser user) async {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the room owner can kick users')),
      );
      return;
    }
    if (user.userId == currentUserId) return;

    setState(() {
      users = users.where((item) => item.userId != user.userId).toList();
    });

    try {
      await roomService.kickUser(
        roomId: widget.roomId,
        userId: user.userId,
        name: user.name,
        image: user.image,
      );

      unawaited(roomService.sendNotification(
        toUserId: user.userId,
        type: 'kicked',
        title: 'تم طردك من الروم',
        body: '$currentUserName قام بطردك من الروم',
        fromUserId: currentUserId,
        fromName: currentUserName,
        fromImage: currentUserImage,
        roomId: widget.roomId,
      ));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} تم طرده من الروم')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الطرد: $e')),
      );
    }
  }

  void showRoomUsers() {
    setState(() => _showUsersPanel = true);
  }

  Future<void> _inviteUserFromPanel(RoomUser user) async {
    try {
      await roomService.inviteUserToRoom(
        roomId: widget.roomId,
        roomTitle: widget.room.title,
        roomImage: widget.room.image,
        ownerId: currentUserId,
        ownerName: currentUserName,
        invitedUserId: user.userId,
        invitedUserName: user.name,
        invitedUserImage: user.image,
      );
      unawaited(roomService.sendNotification(
        toUserId: user.userId,
        type: 'roomInvite',
        title: 'دعوة للانضمام إلى روم',
        body: '$currentUserName يدعوك للانضمام إلى ${widget.room.title}',
        fromUserId: currentUserId,
        fromName: currentUserName,
        fromImage: currentUserImage,
        roomId: widget.roomId,
        roomTitle: widget.room.title,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال الدعوة إلى ${user.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إرسال الدعوة: $e')),
      );
    }
  }

  Widget _buildUsersPanel() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 330,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          border: Border(
            right: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 90, 18, 20),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StreamBuilder(
            stream: _membersPanelStream,
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
              final panelCutoff = DateTime.now().subtract(
                const Duration(seconds: 75),
              );
              final roomUsers = docs
                  .where((doc) {
                    final data = doc.data();
                    if (data['isOnline'] != true) return false;
                    final lastSeen = data['lastSeen'];
                    if (lastSeen == null) return true;
                    return (lastSeen as Timestamp)
                        .toDate()
                        .isAfter(panelCutoff);
                  })
                  .map(
                    (doc) => roomUserFromFirestore(
                      doc.data(),
                      documentId: doc.id,
                    ),
                  )
                  .toList()
                ..sort((a, b) {
                  if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
                  if (a.isMicOn != b.isMicOn) return a.isMicOn ? -1 : 1;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

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

                  final isCurrentUserLeader = roomUsers.any(
                    (item) =>
                        item.userId.trim() == currentUserId.trim() &&
                        item.isLeader,
                  );

                  return RoomUserTile(
                    user: user,
                    isAdmin: isRoomOwner || isCurrentUserLeader,
                    currentUserId: currentUserId,
                    currentUserName: currentUserName,
                    currentUserImage: currentUserImage,
                    roomService: roomService,
                    onToggleMicPermission: () {
                      toggleUserMicPermission(user);
                    },
                    onKick: () {
                      unawaited(kickUser(user));
                    },
                    onMakeLeader: () {
                      unawaited(makeUserLeader(user));
                    },
                    onInvite: () {
                      Navigator.pop(context);
                      unawaited(_inviteUserFromPanel(user));
                    },
                    onPrivateChat: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrivateChatScreen(
                            currentUserId: currentUserId,
                            currentUserName: currentUserName,
                            currentUserImage: currentUserImage,
                            otherUserId: user.userId,
                            otherName: user.name,
                            otherImage: user.image,
                          ),
                        ),
                      );
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


  String countryFlagFromData(Map<String, dynamic> data) {
    final rawCode = (data['countryCode'] ?? data['country'] ?? 'SA')
        .toString()
        .trim()
        .toUpperCase();

    if (rawCode.length != 2) return '🏳️';

    final first = rawCode.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = rawCode.codeUnitAt(1) - 0x41 + 0x1F1E6;

    if (first < 0x1F1E6 ||
        first > 0x1F1FF ||
        second < 0x1F1E6 ||
        second > 0x1F1FF) {
      return '🏳️';
    }

    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  RoomUser roomUserFromFirestore(
    Map<String, dynamic> data, {
    String documentId = '',
  }) {
    final canonicalUserId = documentId.trim().isNotEmpty
        ? documentId.trim()
        : (data['userId'] ?? '').toString().trim();

    final member = RoomMemberModel.fromMap({
      ...data,
      'userId': canonicalUserId,
    });

    final isLeaderUser = data['isLeader'] == true ||
        (currentOwnerId.trim().isNotEmpty &&
            canonicalUserId == currentOwnerId.trim());

    return RoomUser(
      userId: canonicalUserId,
      name: member.name.isEmpty ? 'User' : member.name,
      image: member.image.isEmpty ? 'https://i.pravatar.cc/150?u=$canonicalUserId' : member.image,
      role: isLeaderUser ? 'Owner' : 'Listener',
      countryFlag: countryFlagFromData(data),
      isSpeaker: speakingUserIds.contains(canonicalUserId),
      hasMicPermission: member.hasMicPermission || isLeaderUser,
      isMicOn: member.isMicOn,
      isLeader: isLeaderUser,
    );
  }

  void syncCurrentUserFromMembers(List<RoomUser> roomUsers) {
    final signedInUserId = currentUserId.trim();
    final currentIndex = roomUsers.indexWhere(
      (user) => user.userId.trim() == signedInUserId,
    );

    if (currentIndex == -1) {
      if (_confirmedMembership && !isLeavingRoom && !hasHandledRoomRemoval) {
        hasHandledRoomRemoval = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(handleCurrentUserRemovedFromRoom());
        });
      }
      return;
    }

    _confirmedMembership = true;
    final member = roomUsers[currentIndex];

    // Track mic permission changes and notify the user.
    // everyoneCanUseMic acts as a room-wide grant — include it in the check.
    final newPermission = member.hasMicPermission || isRoomOwner || everyoneCanUseMic;
    if (_micPermissionInitialized && newPermission != _lastKnownMicPermission) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (newPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.mic_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('تم منحك صلاحية الميكروفون'),
              ]),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          isMicOn = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.mic_off_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('تم سحب صلاحية الميكروفون'),
              ]),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
    _lastKnownMicPermission = newPermission;
    _micPermissionInitialized = true;

    // Force mic off only when the user truly has no permission.
    // everyoneCanUseMic is a room-wide grant that overrides individual flags.
    final shouldForceMicOff =
        !member.hasMicPermission && !isRoomOwner && !everyoneCanUseMic && isMicOn;

    if (shouldForceMicOff) {
      isMicOn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(liveKitRoom.localParticipant?.setMicrophoneEnabled(false));
        unawaited(roomService.updateMicState(
          roomId: widget.roomId,
          userId: currentUserId,
          isMicOn: false,
        ));
      });
      return;
    }

    if (isMicOn != member.isMicOn) {
      isMicOn = member.isMicOn;
    }
  }

  Future<void> handleCurrentUserRemovedFromRoom() async {
    if (!mounted || isLeavingRoom) return;

    isLeavingRoom = true;
    await disconnectVoiceRoom();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You were removed from this room')),
    );

    Navigator.pop(context);
  }

  Widget _buildBannerAd() {
    // On Android/iOS show the real AdMob banner once it loads.
    if (!kIsWeb && _isBannerAdLoaded && _bannerAd != null) {
      return Container(
        width: double.infinity,
        height: _bannerAd!.size.height.toDouble(),
        color: Colors.black.withOpacity(0.22),
        alignment: Alignment.center,
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }

    // On web (dev only) or while the ad is still loading — show nothing.
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmExitRoom());
      },
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder(
          stream: _membersPanelStream,
          builder: (context, membersSnapshot) {
            final docs = membersSnapshot.data?.docs ?? [];

            // Presence cutoff: same threshold as the server-side cleanup (75 s).
            final presenceCutoff = DateTime.now().subtract(
              const Duration(seconds: 75),
            );

            users = docs
                .where((doc) {
                  final data = doc.data();
                  // Must be explicitly marked online.
                  if (data['isOnline'] != true) return false;
                  // lastSeen must be fresh — if null the server timestamp is
                  // still pending (brand-new join), so include it.
                  final lastSeen = data['lastSeen'];
                  if (lastSeen == null) return true;
                  return (lastSeen as Timestamp)
                      .toDate()
                      .isAfter(presenceCutoff);
                })
                .map(
                  (doc) => roomUserFromFirestore(
                    doc.data(),
                    documentId: doc.id,
                  ),
                )
                .where((user) {
                  final id = user.userId.toLowerCase();
                  final name = user.name.toLowerCase();
                  return !id.startsWith('bot_') &&
                      id != 'user_mohammed' &&
                      id != 'mohammed' &&
                      !id.contains('bot') &&
                      !name.contains('bot');
                })
                .toList()
              ..sort((a, b) {
                if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
                if (a.isMicOn != b.isMicOn) return a.isMicOn ? -1 : 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

            syncCurrentUserFromMembers(users);

            final topUsers = users
                .where((user) => user.isMicOn)
                .toList()
              ..sort((a, b) {
                if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

            return AnimatedWaveRoomBackground(
              controller: backgroundController,
              child: Stack(
                children: [
                  SafeArea(
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
                          if (topUsers.isNotEmpty)
                            SizedBox(
                              height: 68,
                              width: 170,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: topUsers.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 14),
                                itemBuilder: (context, index) {
                                  final activeUser = topUsers[index];
                                  return SpeakerAvatar(
                                    user: activeUser,
                                    radius: 22,
                                    isSpeaking: activeUser.isSpeaker,
                                    showName: false,
                                  );
                                },
                              ),
                            )
                          else
                            const SizedBox(width: 170),
                          const Spacer(),
                          IconButton(
                            onPressed: showRoomMenu,
                            icon: const Icon(
                              Icons.menu_rounded,
                              color: Colors.white,
                              size: 32,
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
                    if (needsAudioPlaybackTap)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: startAudioPlayback,
                            icon: const Icon(Icons.volume_up_rounded),
                            label: const Text('Play voice'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
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
                    _buildBannerAd(),
                  ],
                ),
              ),
              if (_showUsersPanel)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _showUsersPanel = false),
                    child: Container(color: Colors.black.withOpacity(0.35)),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                left: _showUsersPanel ? 0 : -330,
                top: 0,
                bottom: 0,
                width: 330,
                child: _buildUsersPanel(),
              ),
            ],
          ),
        );
          },
        ),
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
    messagesStream = safeFirestoreStream(widget.roomService.messagesStream(widget.roomId));

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
  final String countryFlag;
  final bool isSpeaker;
  final bool isLeader;
  final bool isMicOn;
  bool hasMicPermission;

  RoomUser({
    this.userId = '',
    required this.name,
    required this.image,
    required this.role,
    this.countryFlag = '🇸🇦',
    required this.isSpeaker,
    required this.hasMicPermission,
    required this.isMicOn,
    this.isLeader = false,
  });


  RoomUser copyWith({
    String? userId,
    String? name,
    String? image,
    String? role,
    String? countryFlag,
    bool? isSpeaker,
    bool? isLeader,
    bool? isMicOn,
    bool? hasMicPermission,
  }) {
    return RoomUser(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      image: image ?? this.image,
      role: role ?? this.role,
      countryFlag: countryFlag ?? this.countryFlag,
      isSpeaker: isSpeaker ?? this.isSpeaker,
      isLeader: isLeader ?? this.isLeader,
      isMicOn: isMicOn ?? this.isMicOn,
      hasMicPermission: hasMicPermission ?? this.hasMicPermission,
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


        if (isLeader)
          Positioned(
            top: -(effectiveCrownSize * 1.20),
            child: CustomPaint(
              size: Size(effectiveCrownSize * 1.95, effectiveCrownSize * 1.22),
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
    final double w = size.width;
    final double h = size.height;

    // Crown silhouette — 4-spike white crown matching reference image
    final Path crown = Path()
      ..moveTo(w * 0.05, h * 0.82)
      ..lineTo(w * 0.13, h * 0.34)     // outer-left slope
      ..lineTo(w * 0.28, h * 0.60)     // left valley
      ..lineTo(w * 0.40, h * 0.05)     // inner-left peak (tall)
      ..lineTo(w * 0.50, h * 0.38)     // center dip
      ..lineTo(w * 0.60, h * 0.05)     // inner-right peak (tall)
      ..lineTo(w * 0.72, h * 0.60)     // right valley
      ..lineTo(w * 0.87, h * 0.34)     // outer-right slope
      ..lineTo(w * 0.95, h * 0.82)     // bottom-right
      ..quadraticBezierTo(w * 0.50, h * 0.97, w * 0.05, h * 0.82)
      ..close();

    // Drop shadow
    canvas.drawPath(
      crown.shift(const Offset(0, 2.8)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Solid white fill
    canvas.drawPath(crown, Paint()..color = Colors.white);

    // Thin grey outline for crisp edges
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x33000000),
    );

    // Inner highlight along the top spikes
    final Path spikes = Path()
      ..moveTo(w * 0.13, h * 0.34)
      ..lineTo(w * 0.28, h * 0.60)
      ..lineTo(w * 0.40, h * 0.05)
      ..lineTo(w * 0.50, h * 0.38)
      ..lineTo(w * 0.60, h * 0.05)
      ..lineTo(w * 0.72, h * 0.60)
      ..lineTo(w * 0.87, h * 0.34);

    canvas.drawPath(
      spikes,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x28000000),
    );
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

class RoomUserTile extends StatefulWidget {
  const RoomUserTile({
    super.key,
    required this.user,
    required this.isAdmin,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.roomService,
    required this.onToggleMicPermission,
    required this.onKick,
    required this.onMakeLeader,
    this.onInvite,
    this.onPrivateChat,
  });

  final RoomUser user;
  final bool isAdmin;
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final RoomService roomService;
  final VoidCallback onToggleMicPermission;
  final VoidCallback onKick;
  final VoidCallback onMakeLeader;
  final VoidCallback? onInvite;
  final VoidCallback? onPrivateChat;

  @override
  State<RoomUserTile> createState() => _RoomUserTileState();
}

class _RoomUserTileState extends State<RoomUserTile> {
  StreamSubscription<dynamic>? _friendSub;
  String _friendStatus = 'none';

  bool get isCurrentUser =>
      widget.user.userId.trim() == widget.currentUserId.trim();

  @override
  void initState() {
    super.initState();
    if (!isCurrentUser) {
      _friendSub = widget.roomService
          .friendLinkStream(
            currentUserId: widget.currentUserId,
            otherUserId: widget.user.userId,
          )
          .listen((doc) {
        final data = (doc as dynamic)?.data() as Map<String, dynamic>?;
        final status = (data?['status'] ?? 'none').toString();
        if (mounted) setState(() => _friendStatus = status);
      });
    }
  }

  @override
  void dispose() {
    _friendSub?.cancel();
    super.dispose();
  }

  Future<void> _handleFriendAction() async {
    try {
      if (_friendStatus == 'pending_sent') {
        await widget.roomService.cancelFriendRequest(
          fromUserId: widget.currentUserId,
          toUserId: widget.user.userId,
        );
      } else if (_friendStatus == 'pending_received') {
        await widget.roomService.acceptFriendRequest(
          currentUserId: widget.currentUserId,
          currentName: widget.currentUserName,
          currentImage: widget.currentUserImage,
          otherUserId: widget.user.userId,
          otherName: widget.user.name,
          otherImage: widget.user.image,
        );
      } else if (_friendStatus == 'friends') {
        await widget.roomService.removeFriend(
          currentUserId: widget.currentUserId,
          otherUserId: widget.user.userId,
        );
      } else {
        await widget.roomService.sendFriendRequest(
          fromUserId: widget.currentUserId,
          fromName: widget.currentUserName,
          fromImage: widget.currentUserImage,
          toUserId: widget.user.userId,
          toName: widget.user.name,
          toImage: widget.user.image,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشلت العملية: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLeaderUser =
        widget.user.isLeader || widget.user.role.toLowerCase() == 'owner';
    final targetUserId = widget.user.userId.trim();
    final signedInUserId = widget.currentUserId.trim();
    final canManageUser = widget.isAdmin &&
        targetUserId.isNotEmpty &&
        targetUserId != signedInUserId;

    final menuItems = <PopupMenuEntry<String>>[];

    if (!isCurrentUser) {
      // Friend action — label/icon changes based on current status
      IconData friendIcon;
      Color friendColor;
      String friendLabel;
      if (_friendStatus == 'pending_sent') {
        friendIcon = Icons.check_circle_rounded;
        friendColor = Colors.greenAccent;
        friendLabel = 'سحب طلب الصداقة';
      } else if (_friendStatus == 'pending_received') {
        friendIcon = Icons.person_add_alt_rounded;
        friendColor = Colors.orangeAccent;
        friendLabel = 'قبول طلب الصداقة';
      } else if (_friendStatus == 'friends') {
        friendIcon = Icons.people_alt_rounded;
        friendColor = Colors.lightBlueAccent;
        friendLabel = 'إزالة صديق';
      } else {
        friendIcon = Icons.person_add_alt_1_rounded;
        friendColor = Colors.white70;
        friendLabel = 'إضافة صديق';
      }
      menuItems.add(PopupMenuItem<String>(
        value: 'friend',
        child: Row(children: [
          Icon(friendIcon, color: friendColor, size: 20),
          const SizedBox(width: 8),
          Text(friendLabel, style: const TextStyle(color: Colors.white)),
        ]),
      ));

      // Private chat — only when friends
      if (_friendStatus == 'friends' && widget.onPrivateChat != null) {
        menuItems.add(const PopupMenuItem<String>(
          value: 'private_chat',
          child: Row(children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: Colors.lightBlueAccent, size: 20),
            SizedBox(width: 8),
            Text('رسالة خاصة', style: TextStyle(color: Colors.white)),
          ]),
        ));
      }

      // Invite to room
      if (widget.onInvite != null) {
        menuItems.add(const PopupMenuItem<String>(
          value: 'invite',
          child: Row(children: [
            Icon(Icons.send_rounded, color: Colors.purpleAccent, size: 20),
            SizedBox(width: 8),
            Text('دعوة للروم', style: TextStyle(color: Colors.white)),
          ]),
        ));
      }
    }

    if (canManageUser) {
      // Mic toggle — single item: green = grant, red = revoke
      menuItems.add(PopupMenuItem<String>(
        value: 'mic',
        child: Row(children: [
          Icon(
            widget.user.hasMicPermission
                ? Icons.mic_off_rounded
                : Icons.mic_rounded,
            color: widget.user.hasMicPermission
                ? Colors.redAccent
                : Colors.greenAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            widget.user.hasMicPermission ? 'سحب المايك' : 'إعطاء مايك',
            style: const TextStyle(color: Colors.white),
          ),
        ]),
      ));

      menuItems.add(const PopupMenuItem<String>(
        value: 'make_leader',
        child: Row(children: [
          Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 20),
          SizedBox(width: 8),
          Text('تعيين ليدر', style: TextStyle(color: Colors.white)),
        ]),
      ));

      menuItems.add(const PopupMenuItem<String>(
        value: 'kick',
        child: Row(children: [
          Icon(Icons.block_rounded, color: Colors.redAccent, size: 20),
          SizedBox(width: 8),
          Text('طرد', style: TextStyle(color: Colors.white)),
        ]),
      ));
    }

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
            image: widget.user.image,
            radius: 26,
            isLeader: isLeaderUser,
          ),
          const SizedBox(width: 10),
          Text(widget.user.countryFlag,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isCurrentUser && menuItems.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  color: Colors.white70, size: 22),
              color: const Color(0xFF21153E),
              onSelected: (value) {
                if (value == 'friend') unawaited(_handleFriendAction());
                if (value == 'private_chat') widget.onPrivateChat?.call();
                if (value == 'invite') widget.onInvite?.call();
                if (value == 'mic') widget.onToggleMicPermission();
                if (value == 'make_leader') widget.onMakeLeader();
                if (value == 'kick') widget.onKick();
              },
              itemBuilder: (context) => menuItems,
            ),
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

