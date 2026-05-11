import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/room.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.room});

  final Room room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final YoutubePlayerController youtubeController;

  final List<SpeakerUser> speakers = const [
    SpeakerUser(name: 'محمد', image: 'https://i.pravatar.cc/150?img=11'),
    SpeakerUser(name: 'فهد', image: 'https://i.pravatar.cc/150?img=12'),
    SpeakerUser(name: 'ناصر', image: 'https://i.pravatar.cc/150?img=13'),
    SpeakerUser(name: 'سلمان', image: 'https://i.pravatar.cc/150?img=14'),
    SpeakerUser(name: 'تركي', image: 'https://i.pravatar.cc/150?img=15'),
    SpeakerUser(name: 'عبدالله', image: 'https://i.pravatar.cc/150?img=16'),
  ];

  final String activeSpeakerName = 'فهد';

  @override
  void initState() {
    super.initState();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSpeaker = speakers.firstWhere(
      (speaker) => speaker.name == activeSpeakerName,
      orElse: () => speakers.first,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
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
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const Spacer(),
                      SpeakerAvatar(
                        speaker: activeSpeaker,
                        radius: 26,
                        isSpeaking: true,
                        showName: true,
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
                        onPressed: () {},
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
                    child: ListView(
                      children: const [
                        Text(
                          'محمد دخل الروم',
                          style: TextStyle(color: Colors.white54),
                        ),
                        SizedBox(height: 12),
                        ChatBubble(
                          name: 'فهد',
                          message: 'الصوت واضح؟',
                        ),
                        SizedBox(height: 12),
                        ChatBubble(
                          name: 'ناصر',
                          message: 'شغل المقطع اللي بعده',
                        ),
                      ],
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
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic, size: 38),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          alignment: Alignment.centerRight,
                          child: const Text(
                            'دردش',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.image, color: Colors.white, size: 28),
                      const SizedBox(width: 10),
                      const Icon(Icons.link, color: Colors.white, size: 28),
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
                      'مكان الإعلان',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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

class SpeakerUser {
  final String name;
  final String image;

  const SpeakerUser({
    required this.name,
    required this.image,
  });
}

class SpeakerAvatar extends StatefulWidget {
  const SpeakerAvatar({
    super.key,
    required this.speaker,
    required this.radius,
    required this.isSpeaking,
    this.showName = true,
  });

  final SpeakerUser speaker;
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
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      ),
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
              child: Container(
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
                  backgroundImage: NetworkImage(widget.speaker.image),
                ),
              ),
            );
          },
        ),
        if (widget.showName) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: widget.radius * 2.4,
            child: Text(
              widget.speaker.name,
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

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.name,
    required this.message,
  });

  final String name;
  final String message;

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
              text: '$name: ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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