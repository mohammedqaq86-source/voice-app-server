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
  const ReplyTarget({required this.name, required this.message});
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomScreen widget
// ─────────────────────────────────────────────────────────────────────────────

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
  // ── Controllers ─────────────────────────────────────────────────────────────
  late final YoutubePlayerController youtubeController;
  final TextEditingController chatController = TextEditingController();
  final ScrollController chatScrollController = ScrollController();
  final RoomService roomService = RoomService();
  late final AnimationController backgroundController;

  // ── LiveKit ──────────────────────────────────────────────────────────────────
  static const String _liveKitUrl = 'wss://mohammed-54ar6zrx.livekit.cloud';
  static const String _liveKitTokenEndpoint =
      'https://voice-app-server-ssrz.onrender.com/token';
  final livekit.Room liveKitRoom = livekit.Room();

  // ── Ads ──────────────────────────────────────────────────────────────────────
  final AdService _adService = AdService();
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  // ── Timers ───────────────────────────────────────────────────────────────────
  Timer? _speakingMonitorTimer;
  Timer? _heartbeatTimer;
  Timer? _pauseLeaveTimer;
  int _heartbeatTick = 0;

  // ── Voice state ──────────────────────────────────────────────────────────────
  Set<String> _speakingUserIds = {};
  bool isVoiceConnected = false;
  bool isConnectingVoice = false;
  bool needsAudioPlaybackTap = false;
  bool isMicOn = false;

  // ── Room state ───────────────────────────────────────────────────────────────
  bool hasJoinedRoom = false;
  bool isLeavingRoom = false;
  bool _hasHandledRoomRemoval = false;
  bool _confirmedMembership = false;
  bool everyoneCanUseMic = false;
  bool _canPopNow = false;
  bool _isConfirmingExit = false;
  bool _showUsersPanel = false;
  bool _lastKnownMicPermission = false;
  bool _micPermissionInitialized = false;
  late bool isPrivateRoom;

  // ── Subscriptions ────────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;

  // ── Room info ────────────────────────────────────────────────────────────────
  String currentOwnerId = '';
  String currentOwnerName = '';
  String currentOwnerImage = '';

  // ── Members / chat ───────────────────────────────────────────────────────────
  List<RoomUser> _users = [];
  ReplyTarget? replyTarget;

  // ── Firebase shortcuts ───────────────────────────────────────────────────────
  User? get _firebaseUser => FirebaseAuth.instance.currentUser;
  String get currentUserId => _firebaseUser?.uid ?? 'guest_user';

  String get currentUserName {
    final displayName = _firebaseUser?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = _firebaseUser?.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'User';
  }

  String get currentUserImage {
    final photoUrl = _firebaseUser?.photoURL?.trim();
    if (photoUrl != null && photoUrl.isNotEmpty) return photoUrl;
    return 'https://i.pravatar.cc/150?u=$currentUserId';
  }

  bool get isRoomOwner {
    final id = currentOwnerId.trim();
    return id.isNotEmpty && id == currentUserId;
  }

  bool get canManageRoom => isRoomOwner || _currentUser.isLeader;

  RoomUser get _currentUser => _users.firstWhere(
        (u) => u.userId == currentUserId,
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

  bool get hasMicPermission =>
      _currentUser.hasMicPermission || everyoneCanUseMic || isRoomOwner;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isPrivateRoom = widget.room.isPrivate;
    currentOwnerId = widget.room.ownerId;
    currentOwnerName = widget.room.ownerName;
    currentOwnerImage = widget.room.ownerImage;

    // Members subscription — single source of truth for _users list
    _membersSub = safeFirestoreStream(roomService.membersStream(widget.roomId))
        .listen((snapshot) {
      if (!mounted) return;
      _processMembersSnapshot(snapshot);
    });

    // Room doc subscription — tracks owner / privacy / allMicEnabled
    _roomSub = safeFirestoreStream(roomService.roomStream(widget.roomId))
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (data == null) return;
      setState(() {
        currentOwnerId = (data['ownerId'] ?? '').toString();
        currentOwnerName = (data['ownerName'] ?? '').toString();
        currentOwnerImage = (data['ownerImage'] ?? '').toString();
        isPrivateRoom = data['isPrivate'] == true;
        everyoneCanUseMic = data['allMicEnabled'] == true;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureCurrentUserIsMember();
      if (!mounted) return;
      unawaited(connectVoiceRoom());
    });

    backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    youtubeController = YoutubePlayerController(
      initialVideoId: widget.room.videoId,
      flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
    );

    _loadBannerAd();

    listenForPageUnload(() {
      if (!isLeavingRoom && hasJoinedRoom && currentUserId != 'guest_user') {
        isLeavingRoom = true;
        _heartbeatTimer?.cancel();
        unawaited(
            roomService.leaveRoom(roomId: widget.roomId, userId: currentUserId));
      }
    });
  }

  // Processes Firestore members snapshot into _users without any side-effects
  // that would call setState — the setState is the outer one in the listener.
  void _processMembersSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 75));

    final newUsers = snapshot.docs
        .where((doc) {
          final data = doc.data();
          if (data['isOnline'] != true) return false;
          final lastSeen = data['lastSeen'];
          if (lastSeen == null) return true;
          return (lastSeen as Timestamp).toDate().isAfter(cutoff);
        })
        .map((doc) => _roomUserFromDoc(doc.data(), documentId: doc.id))
        .where((u) {
          final id = u.userId.toLowerCase();
          final name = u.name.toLowerCase();
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

    setState(() => _users = newUsers);
    _syncCurrentUserFromMembers(newUsers);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pauseLeaveTimer?.cancel();
      _pauseLeaveTimer = null;
      if (hasJoinedRoom && !isLeavingRoom && currentUserId != 'guest_user') {
        _startHeartbeat();
        unawaited(roomService.updateMemberHeartbeat(
            roomId: widget.roomId, userId: currentUserId));
      }
    } else if (state == AppLifecycleState.paused) {
      _heartbeatTimer?.cancel();
      if (!isLeavingRoom && currentUserId != 'guest_user' && hasJoinedRoom) {
        _pauseLeaveTimer?.cancel();
        _pauseLeaveTimer = Timer(const Duration(minutes: 2), () {
          if (isLeavingRoom) return;
          isLeavingRoom = true;
          unawaited(disconnectVoiceRoom());
          unawaited(roomService.leaveRoom(
              roomId: widget.roomId, userId: currentUserId));
        });
      }
    } else if (state == AppLifecycleState.detached) {
      _pauseLeaveTimer?.cancel();
      _heartbeatTimer?.cancel();
      if (!isLeavingRoom && currentUserId != 'guest_user' && hasJoinedRoom) {
        isLeavingRoom = true;
        unawaited(disconnectVoiceRoom());
        unawaited(roomService.leaveRoom(
            roomId: widget.roomId, userId: currentUserId));
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
    _membersSub?.cancel();
    _roomSub?.cancel();
    _speakingMonitorTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pauseLeaveTimer?.cancel();
    _bannerAd?.dispose();
    _adService.dispose();
    liveKitRoom.disconnect();
    if (!isLeavingRoom && currentUserId != 'guest_user') {
      unawaited(
          roomService.leaveRoom(roomId: widget.roomId, userId: currentUserId));
    }
    super.dispose();
  }

  // ── Ads ──────────────────────────────────────────────────────────────────────
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

  Widget _buildBannerAd() {
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
    return const SizedBox.shrink();
  }

  // ── Heartbeat ────────────────────────────────────────────────────────────────
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 25), (_) {
      if (!hasJoinedRoom || isLeavingRoom || currentUserId == 'guest_user') {
        return;
      }
      _heartbeatTick++;
      unawaited(roomService.updateMemberHeartbeat(
          roomId: widget.roomId, userId: currentUserId));
      if (_heartbeatTick % 3 == 0) {
        unawaited(roomService.cleanupStaleMembers(
            roomId: widget.roomId, excludeUserId: currentUserId));
      }
    });
  }

  // ── Join ─────────────────────────────────────────────────────────────────────
  Future<void> _ensureCurrentUserIsMember() async {
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
      _adService.loadInterstitial();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to join room: $e')));
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────────────
  Future<String> _getLiveKitToken() async {
    final response = await http.post(
      Uri.parse(_liveKitTokenEndpoint),
      headers: const {'Content-Type': 'application/json'},
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
    if (token == null || token.isEmpty) throw Exception('Token is empty');
    return token;
  }

  Future<void> connectVoiceRoom() async {
    if (isVoiceConnected || isConnectingVoice) return;
    setState(() => isConnectingVoice = true);
    try {
      final token = await _getLiveKitToken();
      await liveKitRoom.connect(_liveKitUrl, token);
      await liveKitRoom.localParticipant?.setMicrophoneEnabled(false);
      await startAudioPlayback();
      if (!mounted) return;
      setState(() {
        isVoiceConnected = true;
        isConnectingVoice = false;
      });
      _startSpeakingMonitor();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isVoiceConnected = false;
        isConnectingVoice = false;
        _speakingUserIds = {};
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to connect voice: $e')));
    }
  }

  Future<void> startAudioPlayback() async {
    try {
      await liveKitRoom.startAudio();
      if (!mounted) return;
      setState(() => needsAudioPlaybackTap = !liveKitRoom.canPlaybackAudio);
    } catch (_) {
      if (!mounted) return;
      setState(() => needsAudioPlaybackTap = true);
    }
  }

  void _startSpeakingMonitor() {
    _speakingMonitorTimer?.cancel();
    _speakingMonitorTimer =
        Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted || !isVoiceConnected) return;
      final active = liveKitRoom.activeSpeakers
          .map((p) => p.identity)
          .whereType<String>()
          .toSet();
      if (setEquals(active, _speakingUserIds)) return;
      setState(() => _speakingUserIds = active);
    });
  }

  void _stopSpeakingMonitor() {
    _speakingMonitorTimer?.cancel();
    _speakingMonitorTimer = null;
    if (!mounted) return;
    setState(() => _speakingUserIds = {});
  }

  Future<void> disconnectVoiceRoom() async {
    _stopSpeakingMonitor();
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
          const SnackBar(content: Text('ليس لديك صلاحية الميكروفون')));
      return;
    }
    final previousMicState = isMicOn;
    final newMicState = !isMicOn;
    if (newMicState && !kIsWeb) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')));
        return;
      }
    }
    setState(() => isMicOn = newMicState);
    unawaited(roomService.updateMicState(
        roomId: widget.roomId, userId: currentUserId, isMicOn: newMicState));
    await connectVoiceRoom();
    if (!isVoiceConnected) {
      if (!mounted) return;
      setState(() => isMicOn = previousMicState);
      unawaited(roomService.updateMicState(
          roomId: widget.roomId,
          userId: currentUserId,
          isMicOn: previousMicState));
      return;
    }
    await startAudioPlayback();
    try {
      await liveKitRoom.localParticipant?.setMicrophoneEnabled(newMicState);
    } catch (e) {
      if (!mounted) return;
      setState(() => isMicOn = previousMicState);
      unawaited(roomService.updateMicState(
          roomId: widget.roomId,
          userId: currentUserId,
          isMicOn: previousMicState));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل تشغيل الميكروفون: $e')));
    }
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────
  Future<void> sendMessage() async {
    final text = chatController.text.trim();
    if (text.isEmpty) return;
    final mentions = RegExp(r'@([\w؀-ۿ]+)')
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final currentReply = replyTarget;
    chatController.clear();
    setState(() => replyTarget = null);
    await roomService.sendMessage(
      roomId: widget.roomId,
      userId: currentUserId,
      name: currentUserName,
      image: _currentUser.image,
      message: text,
      isLeader: _currentUser.isLeader,
      replyToName: currentReply?.name,
      replyToMessage: currentReply?.message,
      mentions: mentions,
    );
  }

  void _setReplyTarget(String name, String message) {
    setState(() => replyTarget = ReplyTarget(name: name, message: message));
  }

  void _showMentionUsers() {
    if (_users.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No users in room')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _users.length,
            itemBuilder: (context, index) {
              final user = _users[index];
              return ListTile(
                leading:
                    CircleAvatar(backgroundImage: NetworkImage(user.image)),
                title: Text(user.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () {
                  final old = chatController.text;
                  final mention = '@${user.name} ';
                  chatController.text =
                      old.isEmpty ? mention : '$old $mention';
                  chatController.selection = TextSelection.fromPosition(
                      TextPosition(offset: chatController.text.length));
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  // ── Exit ─────────────────────────────────────────────────────────────────────
  Future<void> confirmExitRoom() async {
    if (_isConfirmingExit || isLeavingRoom) return;
    _isConfirmingExit = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave room'),
        content: const Text('Are you sure you want to leave this room?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes')),
        ],
      ),
    );
    if (shouldExit != true || !mounted) {
      _isConfirmingExit = false;
      return;
    }
    final wasUsingMic = isMicOn;
    isLeavingRoom = true;
    await disconnectVoiceRoom();

    Future<void> leaveAndPop() async {
      await roomService.leaveRoom(
          roomId: widget.roomId, userId: currentUserId);
      if (!mounted) return;
      setState(() => _canPopNow = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }

    if (!wasUsingMic && _adService.isInterstitialReady) {
      await _adService
          .showInterstitialAndThen(() => unawaited(leaveAndPop()));
    } else {
      await leaveAndPop();
    }
  }

  Future<void> _handleCurrentUserRemoved() async {
    if (!mounted || isLeavingRoom) return;
    isLeavingRoom = true;
    await disconnectVoiceRoom();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You were removed from this room')));
    setState(() => _canPopNow = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  // ── Room menu / settings ─────────────────────────────────────────────────────
  void _showRoomMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
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
                      borderRadius: BorderRadius.circular(20)),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading:
                      const Icon(Icons.people_alt_rounded, color: Colors.white),
                  title: const Text('قائمة الأصدقاء',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _showInviteFriendsSheet();
                  },
                ),
                if (canManageRoom)
                  ListTile(
                    leading:
                        const Icon(Icons.settings_rounded, color: Colors.white),
                    title: const Text('إعدادات الروم',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _openRoomSettings();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openRoomSettings() {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فقط الليدر يمكنه فتح الإعدادات')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
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
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    const SizedBox(height: 22),
                    const Text('إعدادات الروم',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      value: isPrivateRoom,
                      activeColor: Colors.white,
                      title: const Text('روم خاص',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('فقط المدعوون يمكنهم الدخول',
                          style: TextStyle(color: Colors.white54)),
                      onChanged: (value) {
                        setSheet(() {});
                        setState(() => isPrivateRoom = value);
                        unawaited(roomService.updateRoomPrivacy(
                            roomId: widget.roomId, isPrivate: value));
                      },
                    ),
                    SwitchListTile(
                      value: everyoneCanUseMic,
                      activeColor: Colors.white,
                      title: const Text('السماح للجميع بالمايك',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'يسمح لجميع الأعضاء بتشغيل المايك',
                          style: TextStyle(color: Colors.white54)),
                      onChanged: (value) {
                        setSheet(() {});
                        if (value) {
                          unawaited(roomService.enableMicForAll(
                              roomId: widget.roomId));
                        } else {
                          unawaited(roomService.disableMicForAll(
                              roomId: widget.roomId));
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
                              await roomService.enableMicForAll(
                                  roomId: widget.roomId);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('تم تفعيل المايك للجميع')));
                            },
                            icon: const Icon(Icons.mic_rounded,
                                color: Colors.greenAccent),
                            label: const Text('تفعيل المايك للكل',
                                style: TextStyle(color: Colors.greenAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color:
                                      Colors.greenAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await roomService.disableMicForAll(
                                  roomId: widget.roomId);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('تم تعطيل المايك للجميع')));
                            },
                            icon: const Icon(Icons.mic_off_rounded,
                                color: Colors.redAccent),
                            label: const Text('تعطيل المايك للكل',
                                style: TextStyle(color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: Colors.redAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
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

  // ── Invite friends ───────────────────────────────────────────────────────────
  void _showInviteFriendsSheet() {
    final friendsStream =
        safeFirestoreStream(roomService.friendsStream(userId: currentUserId));
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17112F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
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
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1_rounded,
                            color: Colors.white, size: 26),
                        SizedBox(width: 10),
                        Text('دعوة أصدقاء للروم',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
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
                              child: Text('لا يوجد أصدقاء لدعوتهم',
                                  style: TextStyle(color: Colors.white54)));
                        }
                        return ListView.builder(
                          controller: scrollController,
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            final friendId = docs[index].id;
                            final friendName =
                                (data['name'] ?? 'User').toString();
                            final friendImage =
                                (data['image'] ?? '').toString();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: friendImage.isNotEmpty
                                      ? NetworkImage(friendImage)
                                      : null,
                                  child: friendImage.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                title: Text(friendName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
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
                                        body:
                                            '$currentUserName يدعوك للانضمام إلى ${widget.room.title}',
                                        fromUserId: currentUserId,
                                        fromName: currentUserName,
                                        fromImage: currentUserImage,
                                        roomId: widget.roomId,
                                        roomTitle: widget.room.title,
                                      ));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'تم إرسال الدعوة إلى $friendName')));
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'فشل إرسال الدعوة: $e')));
                                    }
                                  },
                                  icon: const Icon(Icons.send_rounded,
                                      size: 16),
                                  label: const Text('دعوة'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withOpacity(0.15),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
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

  // ── Member management ────────────────────────────────────────────────────────
  Future<void> _makeUserLeader(RoomUser user) async {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Only the room owner can assign leaders')));
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
          SnackBar(content: Text('${user.name} أصبح ليدر الروم')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل نقل القيادة: $e')));
    }
  }

  Future<void> _toggleUserMicPermission(RoomUser user) async {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Only the room owner can control mic')));
      return;
    }
    if (user.userId.trim().isEmpty) return;
    final newPermission = !user.hasMicPermission;
    setState(() {
      _users = _users.map((item) {
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
          hasMicPermission: newPermission);
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
        title:
            newPermission ? 'تم منحك الميكروفون 🎙️' : 'تم سحب الميكروفون',
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
        _users = _users.map((item) {
          if (item.userId != user.userId) return item;
          return item.copyWith(
              hasMicPermission: user.hasMicPermission, isMicOn: user.isMicOn);
        }).toList();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update mic: $e')));
    }
  }

  Future<void> _kickUser(RoomUser user) async {
    if (!canManageRoom) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Only the room owner can kick users')));
      return;
    }
    if (user.userId == currentUserId) return;
    setState(() =>
        _users = _users.where((u) => u.userId != user.userId).toList());
    try {
      await roomService.kickUser(
          roomId: widget.roomId,
          userId: user.userId,
          name: user.name,
          image: user.image);
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
          SnackBar(content: Text('${user.name} تم طرده من الروم')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل الطرد: $e')));
    }
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
        body:
            '$currentUserName يدعوك للانضمام إلى ${widget.room.title}',
        fromUserId: currentUserId,
        fromName: currentUserName,
        fromImage: currentUserImage,
        roomId: widget.roomId,
        roomTitle: widget.room.title,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الدعوة إلى ${user.name}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل إرسال الدعوة: $e')));
    }
  }

  // ── Member sync ──────────────────────────────────────────────────────────────
  void _syncCurrentUserFromMembers(List<RoomUser> roomUsers) {
    final signedInId = currentUserId.trim();
    final idx =
        roomUsers.indexWhere((u) => u.userId.trim() == signedInId);

    if (idx == -1) {
      if (_confirmedMembership &&
          !isLeavingRoom &&
          !_hasHandledRoomRemoval) {
        _hasHandledRoomRemoval = true;
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_handleCurrentUserRemoved()));
      }
      return;
    }

    _confirmedMembership = true;
    final member = roomUsers[idx];

    final newPermission =
        member.hasMicPermission || isRoomOwner || everyoneCanUseMic;
    if (_micPermissionInitialized &&
        newPermission != _lastKnownMicPermission) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (newPermission) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.mic_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('تم منحك صلاحية الميكروفون'),
            ]),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ));
        } else {
          isMicOn = false;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.mic_off_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('تم سحب صلاحية الميكروفون'),
            ]),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ));
        }
      });
    }
    _lastKnownMicPermission = newPermission;
    _micPermissionInitialized = true;

    final shouldForceMicOff = !member.hasMicPermission &&
        !isRoomOwner &&
        !everyoneCanUseMic &&
        isMicOn;
    if (shouldForceMicOff) {
      isMicOn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
            liveKitRoom.localParticipant?.setMicrophoneEnabled(false));
        unawaited(roomService.updateMicState(
            roomId: widget.roomId, userId: currentUserId, isMicOn: false));
      });
      return;
    }
    if (isMicOn != member.isMicOn) isMicOn = member.isMicOn;
  }

  // ── Data helpers ─────────────────────────────────────────────────────────────
  RoomUser _roomUserFromDoc(Map<String, dynamic> data,
      {String documentId = ''}) {
    final uid = documentId.trim().isNotEmpty
        ? documentId.trim()
        : (data['userId'] ?? '').toString().trim();

    final member = RoomMemberModel.fromMap({...data, 'userId': uid});

    final isLeader = data['isLeader'] == true ||
        (currentOwnerId.trim().isNotEmpty &&
            uid == currentOwnerId.trim());

    return RoomUser(
      userId: uid,
      name: member.name.isEmpty ? 'User' : member.name,
      image: member.image.isEmpty
          ? 'https://i.pravatar.cc/150?u=$uid'
          : member.image,
      role: isLeader ? 'Owner' : 'Listener',
      countryFlag: _countryFlagFromData(data),
      isSpeaker: false, // recomputed in build from _speakingUserIds
      hasMicPermission: member.hasMicPermission || isLeader,
      isMicOn: member.isMicOn,
      isLeader: isLeader,
    );
  }

  String _countryFlagFromData(Map<String, dynamic> data) {
    final raw = (data['countryCode'] ?? data['country'] ?? 'SA')
        .toString()
        .trim()
        .toUpperCase();
    if (raw.length != 2) return '🏳️';
    final a = raw.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final b = raw.codeUnitAt(1) - 0x41 + 0x1F1E6;
    if (a < 0x1F1E6 || a > 0x1F1FF || b < 0x1F1E6 || b > 0x1F1FF) {
      return '🏳️';
    }
    return String.fromCharCode(a) + String.fromCharCode(b);
  }

  // ── Mic button helpers ───────────────────────────────────────────────────────
  IconData _micIcon() {
    if (!hasMicPermission) return Icons.mic_off_rounded;
    if (isMicOn) return Icons.mic_rounded;
    return Icons.mic_none_rounded;
  }

  Color _micBgColor() {
    if (!hasMicPermission) return Colors.white.withOpacity(0.55);
    if (isMicOn) return Colors.red;
    return Colors.white.withOpacity(0.92);
  }

  Color _micIconColor() {
    if (!hasMicPermission) return Colors.black45;
    if (isMicOn) return Colors.white;
    return Colors.black;
  }

  // ── Users panel ──────────────────────────────────────────────────────────────
  Widget _buildUsersPanel() {
    // Merge speaking state into each user for the panel avatar display
    final panelUsers = _users
        .map((u) =>
            u.copyWith(isSpeaker: _speakingUserIds.contains(u.userId)))
        .toList();

    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.88),
        border: Border(
            right: BorderSide(color: Colors.white.withOpacity(0.10))),
      ),
      padding: const EdgeInsets.fromLTRB(18, 90, 18, 20),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: panelUsers.isEmpty
            ? const Center(
                child: Text('No users',
                    style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                physics: const ClampingScrollPhysics(),
                itemCount: panelUsers.length,
                itemBuilder: (context, index) {
                  final user = panelUsers[index];
                  return RoomUserTile(
                    key: ValueKey(user.userId),
                    user: user,
                    isAdmin: canManageRoom,
                    currentUserId: currentUserId,
                    currentUserName: currentUserName,
                    currentUserImage: currentUserImage,
                    roomService: roomService,
                    onToggleMicPermission: () =>
                        _toggleUserMicPermission(user),
                    onKick: () => unawaited(_kickUser(user)),
                    onMakeLeader: () => unawaited(_makeUserLeader(user)),
                    onInvite: () {
                      setState(() => _showUsersPanel = false);
                      unawaited(_inviteUserFromPanel(user));
                    },
                    onPrivateChat: () {
                      setState(() => _showUsersPanel = false);
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
              ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Compute speaking state here so every speaking-monitor setState refresh
    // picks up the latest _speakingUserIds without re-querying Firestore.
    final topUsers = _users
        .where((u) => u.isMicOn)
        .map((u) =>
            u.copyWith(isSpeaker: _speakingUserIds.contains(u.userId)))
        .toList()
      ..sort((a, b) {
        if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return PopScope<Object?>(
      canPop: _canPopNow,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmExitRoom());
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AnimatedWaveRoomBackground(
            controller: backgroundController,
            child: Stack(
              children: [
                // ── Main content ──────────────────────────────────────────
                SafeArea(
                  child: Column(
                    children: [
                      // Header bar
                      SizedBox(
                        height: 78,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: confirmExitRoom,
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 32),
                              ),
                              IconButton(
                                onPressed: _openRoomSettings,
                                icon: const Icon(Icons.settings,
                                    color: Colors.white, size: 30),
                              ),
                              const Spacer(),
                              if (topUsers.isNotEmpty)
                                SizedBox(
                                  height: 68,
                                  width: 170,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: topUsers.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 14),
                                    itemBuilder: (context, i) {
                                      final u = topUsers[i];
                                      return SpeakerAvatar(
                                        user: u,
                                        radius: 22,
                                        isSpeaking: u.isSpeaker,
                                        showName: false,
                                      );
                                    },
                                  ),
                                )
                              else
                                const SizedBox(width: 170),
                              const Spacer(),
                              IconButton(
                                onPressed: _showRoomMenu,
                                icon: const Icon(Icons.menu_rounded,
                                    color: Colors.white, size: 32),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _showUsersPanel = true),
                                icon: const Icon(Icons.groups_rounded,
                                    color: Colors.white, size: 32),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Audio playback prompt
                      if (needsAudioPlaybackTap)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                                    borderRadius:
                                        BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ),

                      // YouTube player
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

                      // Chat messages
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.08)),
                          ),
                          child: ChatMessagesList(
                            key: ValueKey(widget.roomId),
                            roomId: widget.roomId,
                            roomService: roomService,
                            chatScrollController: chatScrollController,
                            onReply: _setReplyTarget,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Chat input bar
                      Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Reply preview
                            if (replyTarget != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withOpacity(0.10),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.white
                                          .withOpacity(0.65),
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Reply to ${replyTarget!.name}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            replyTarget!.message,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(
                                          () => replyTarget = null),
                                      icon: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                          size: 20),
                                    ),
                                  ],
                                ),
                              ),

                            // Input row
                            Row(
                              children: [
                                // Mic button
                                GestureDetector(
                                  onTap: toggleMic,
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      color: _micBgColor(),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _micIcon(),
                                      size: 38,
                                      color: _micIconColor(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  onPressed: _showMentionUsers,
                                  icon: const Icon(
                                      Icons.alternate_email_rounded,
                                      color: Colors.white,
                                      size: 27),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: chatController,
                                    onSubmitted: (_) => sendMessage(),
                                    style: const TextStyle(
                                        color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'Chat',
                                      hintStyle: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 17),
                                      filled: true,
                                      fillColor: Colors.white
                                          .withOpacity(0.12),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: sendMessage,
                                  icon: const Icon(Icons.send_rounded,
                                      color: Colors.white, size: 27),
                                ),
                                IconButton(
                                  onPressed: _showInviteFriendsSheet,
                                  icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      color: Colors.white,
                                      size: 28),
                                ),
                                const Icon(Icons.image,
                                    color: Colors.white, size: 27),
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

                // ── Slide-in users panel ──────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  left: _showUsersPanel ? 0 : -330,
                  top: 0,
                  bottom: 0,
                  width: 330,
                  child: _buildUsersPanel(),
                ),

                // ── Tap-outside overlay to close panel ────────────────────
                if (_showUsersPanel)
                  Positioned(
                    left: 330,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _showUsersPanel = false),
                      child: Container(
                          color: Colors.black.withOpacity(0.35)),
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

// ─────────────────────────────────────────────────────────────────────────────
// ChatMessagesList
// ─────────────────────────────────────────────────────────────────────────────

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
  late final DateTime _sessionStartedAt;
  int _lastCount = 0;
  int _unreadCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    messagesStream =
        safeFirestoreStream(widget.roomService.messagesStream(widget.roomId));
    widget.chatScrollController.addListener(() {
      if (!mounted) return;
      if (_isNearBottom && _unreadCount > 0) {
        setState(() => _unreadCount = 0);
      }
    });
  }

  bool get _isNearBottom {
    if (!widget.chatScrollController.hasClients) return false;
    final pos = widget.chatScrollController.position;
    return pos.maxScrollExtent - pos.pixels <= 20;
  }

  bool _isFromCurrentSession(Map<String, dynamic> data) {
    if ((data['type'] ?? 'message') == 'system') return true;
    final createdAt = data['createdAt'];
    if (createdAt == null) return true;
    try {
      return !(createdAt.toDate() as DateTime).isBefore(_sessionStartedAt);
    } catch (_) {
      return true;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.chatScrollController.hasClients) return;
      await widget.chatScrollController.animateTo(
        widget.chatScrollController.position.maxScrollExtent + 300,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || !widget.chatScrollController.hasClients) return;
        widget.chatScrollController
            .jumpTo(widget.chatScrollController.position.maxScrollExtent);
      });
    });
  }

  ChatItem _parseDoc(Map<String, dynamic> data) {
    if ((data['type'] ?? 'message') == 'system') {
      IconData? icon;
      if (data['iconCodePoint'] != null) {
        icon = IconData(data['iconCodePoint'],
            fontFamily: data['iconFontFamily'] ?? 'MaterialIcons');
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
              child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white)));
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => _isFromCurrentSession(doc.data()))
            .toList();

        final int docCount = docs.length as int;
        final hadMessages = _lastCount > 0;
        final hasNew = docCount > _lastCount;
        final int newAmt = docCount - _lastCount;

        if (hasNew && hadMessages) {
          if (_isNearBottom) {
            _unreadCount = 0;
          } else {
            _unreadCount += newAmt;
          }
        }
        _lastCount = docCount;

        if (docs.isEmpty) {
          return const Center(
              child: Text('No new messages yet',
                  style: TextStyle(color: Colors.white54)));
        }

        return Stack(
          children: [
            ListView.builder(
              controller: widget.chatScrollController,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final item = _parseDoc(docs[index].data());
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
                    key: ValueKey(
                        '${item.name}-${item.message}-$index'),
                    direction: DismissDirection.startToEnd,
                    dismissThresholds: const {
                      DismissDirection.startToEnd: 0.01
                    },
                    movementDuration:
                        const Duration(milliseconds: 80),
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
                      child: const Icon(Icons.reply_rounded,
                          color: Colors.white, size: 26),
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
            if (_unreadCount > 0)
              Positioned(
                left: 12,
                bottom: 12,
                child: GestureDetector(
                  onTap: () {
                    _scrollToBottom();
                    Future.delayed(const Duration(milliseconds: 500),
                        () {
                      if (!mounted) return;
                      setState(() => _unreadCount = 0);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 10)
                      ],
                    ),
                    child: Text(
                      '$_unreadCount new messages',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
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

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

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
  }) =>
      ChatItem._(
          isSystem: true,
          text: text,
          icon: icon,
          customIcon: customIcon,
          image: image,
          isLeader: isLeader);

  factory ChatItem.message({
    required String name,
    required String message,
    bool isLeader = false,
    String? replyToName,
    String? replyToMessage,
    List<String> mentions = const [],
  }) =>
      ChatItem._(
          isSystem: false,
          name: name,
          message: message,
          isLeader: isLeader,
          replyToName: replyToName,
          replyToMessage: replyToMessage,
          mentions: mentions);
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
  }) =>
      RoomUser(
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

// ─────────────────────────────────────────────────────────────────────────────
// RoomUserTile — fixed PopupMenuButton interactivity
// ─────────────────────────────────────────────────────────────────────────────

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

  bool get _isCurrentUser =>
      widget.user.userId.trim() == widget.currentUserId.trim();

  @override
  void initState() {
    super.initState();
    if (!_isCurrentUser) {
      _friendSub = widget.roomService
          .friendLinkStream(
              currentUserId: widget.currentUserId,
              otherUserId: widget.user.userId)
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
            toUserId: widget.user.userId);
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
            otherUserId: widget.user.userId);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشلت العملية: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLeaderUser =
        widget.user.isLeader || widget.user.role.toLowerCase() == 'owner';
    final targetId = widget.user.userId.trim();
    final signedInId = widget.currentUserId.trim();
    final canManage =
        widget.isAdmin && targetId.isNotEmpty && targetId != signedInId;

    final menuItems = <PopupMenuEntry<String>>[];

    if (!_isCurrentUser) {
      // Friend action
      final IconData friendIcon;
      final Color friendColor;
      final String friendLabel;
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
          Text(friendLabel,
              style: const TextStyle(color: Colors.white)),
        ]),
      ));

      if (_friendStatus == 'friends' && widget.onPrivateChat != null) {
        menuItems.add(const PopupMenuItem<String>(
          value: 'private_chat',
          child: Row(children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: Colors.lightBlueAccent, size: 20),
            SizedBox(width: 8),
            Text('رسالة خاصة',
                style: TextStyle(color: Colors.white)),
          ]),
        ));
      }

      if (widget.onInvite != null) {
        menuItems.add(const PopupMenuItem<String>(
          value: 'invite',
          child: Row(children: [
            Icon(Icons.send_rounded,
                color: Colors.purpleAccent, size: 20),
            SizedBox(width: 8),
            Text('دعوة للروم',
                style: TextStyle(color: Colors.white)),
          ]),
        ));
      }
    }

    if (canManage) {
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
          Icon(Icons.workspace_premium_rounded,
              color: Colors.amber, size: 20),
          SizedBox(width: 8),
          Text('تعيين ليدر',
              style: TextStyle(color: Colors.white)),
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
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 4, 12),
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
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (menuItems.isNotEmpty)
                _MemberMenuButton(
                  menuItems: menuItems,
                  onSelected: (value) {
                    switch (value) {
                      case 'friend':
                        unawaited(_handleFriendAction());
                      case 'private_chat':
                        widget.onPrivateChat?.call();
                      case 'invite':
                        widget.onInvite?.call();
                      case 'mic':
                        widget.onToggleMicPermission();
                      case 'make_leader':
                        widget.onMakeLeader();
                      case 'kick':
                        widget.onKick();
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemberMenuButton — tap-reliable three-dots menu for list items
// Uses GestureDetector(HitTestBehavior.opaque) + showMenu to avoid scroll
// gesture competition that PopupMenuButton can lose inside a ListView.
// ─────────────────────────────────────────────────────────────────────────────

class _MemberMenuButton extends StatefulWidget {
  const _MemberMenuButton({
    required this.menuItems,
    required this.onSelected,
  });

  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onSelected;

  @override
  State<_MemberMenuButton> createState() => _MemberMenuButtonState();
}

class _MemberMenuButtonState extends State<_MemberMenuButton> {
  final _key = GlobalKey();

  Future<void> _openMenu() async {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final rect =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final position = RelativeRect.fromRect(rect, Offset.zero & overlayBox.size);
    final String? value = await showMenu<String>(
      context: context,
      position: position,
      items: widget.menuItems,
      color: const Color(0xFF21153E),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    if (mounted && value != null) widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      behavior: HitTestBehavior.opaque,
      onTap: _openMenu,
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.more_vert, color: Colors.white70, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UI widgets
// ─────────────────────────────────────────────────────────────────────────────

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
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scale =
        Tween<double>(begin: 1, end: 1.08).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOut,
    ));
    if (widget.isSpeaking) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SpeakerAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isSpeaking && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
    if (!widget.isSpeaking && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLeader =
        widget.user.isLeader || widget.user.role.toLowerCase() == 'owner';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _scale,
          builder: (_, __) => Transform.scale(
            scale: widget.isSpeaking ? _scale.value : 1,
            child: LeaderGoldAvatar(
              image: widget.user.image,
              radius: widget.radius,
              isLeader: isLeader,
              isSpeaking: widget.isSpeaking,
              crownSize: widget.radius * 0.62,
            ),
          ),
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
                  fontWeight: FontWeight.bold),
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
    final cs = crownSize ?? radius * 0.82;
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
                        spreadRadius: 1.4)
                  ]
                : [],
          ),
          child: CircleAvatar(
              radius: radius, backgroundImage: NetworkImage(image)),
        ),
        if (isLeader)
          Positioned(
            top: -(cs * 1.20),
            child: CustomPaint(
              size: Size(cs * 1.95, cs * 1.22),
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
    final w = size.width;
    final h = size.height;
    final crown = Path()
      ..moveTo(w * 0.05, h * 0.82)
      ..lineTo(w * 0.13, h * 0.34)
      ..lineTo(w * 0.28, h * 0.60)
      ..lineTo(w * 0.40, h * 0.05)
      ..lineTo(w * 0.50, h * 0.38)
      ..lineTo(w * 0.60, h * 0.05)
      ..lineTo(w * 0.72, h * 0.60)
      ..lineTo(w * 0.87, h * 0.34)
      ..lineTo(w * 0.95, h * 0.82)
      ..quadraticBezierTo(w * 0.50, h * 0.97, w * 0.05, h * 0.82)
      ..close();

    canvas.drawPath(
        crown.shift(const Offset(0, 2.8)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawPath(crown, Paint()..color = Colors.white);
    canvas.drawPath(
        crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x33000000));

    final spikes = Path()
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
          ..color = const Color(0x28000000));
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
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
            LeaderGoldAvatar(image: image!, radius: 11, isLeader: isLeader),
            const SizedBox(width: 10),
          ],
          if (customIcon != null) ...[
            Text(customIcon!, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14)),
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

  List<TextSpan> _messageSpans() {
    if (mentions.isEmpty) {
      return [
        TextSpan(
            text: message,
            style: const TextStyle(color: Colors.white70))
      ];
    }
    final mentionSet = mentions.map((n) => '@$n').toSet();
    final spans = <TextSpan>[];
    final parts = message.split(' ');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final textPart = i == parts.length - 1 ? part : '$part ';
      if (mentionSet.contains(part.trim())) {
        spans.add(TextSpan(
            text: textPart,
            style: const TextStyle(
                color: Color(0xFF7DD3FC),
                fontWeight: FontWeight.bold)));
      } else {
        spans.add(TextSpan(
            text: textPart,
            style: const TextStyle(color: Colors.white70)));
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
          if (hasReply)
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
                        width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(replyToName!,
                      style: const TextStyle(
                          color: Color(0xFF7DD3FC),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(replyToMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: '$name ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const TextSpan(
                  text: ': ',
                  style: TextStyle(color: Colors.white)),
              ..._messageSpans(),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated background
// ─────────────────────────────────────────────────────────────────────────────

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
      builder: (_, __) => CustomPaint(
        painter: RoomWaveBackgroundPainter(controller.value),
        child: child,
      ),
    );
  }
}

class RoomWaveBackgroundPainter extends CustomPainter {
  const RoomWaveBackgroundPainter(this.value);
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
    _wave(canvas, size,
        phase: value * math.pi * 2,
        baseY: size.height * 0.30,
        amplitude: 24,
        color: const Color(0xFF7B3FE4).withOpacity(0.20),
        height: size.height * 0.34);
    _wave(canvas, size,
        phase: value * math.pi * 2 + 1.7,
        baseY: size.height * 0.56,
        amplitude: 30,
        color: const Color(0xFF1E88E5).withOpacity(0.16),
        height: size.height * 0.34);
    _wave(canvas, size,
        phase: value * math.pi * 2 + 3.0,
        baseY: size.height * 0.76,
        amplitude: 22,
        color: const Color(0xFFFFA000).withOpacity(0.10),
        height: size.height * 0.28);
  }

  void _wave(Canvas canvas, Size size,
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
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  }

  @override
  bool shouldRepaint(covariant RoomWaveBackgroundPainter old) =>
      old.value != value;
}
