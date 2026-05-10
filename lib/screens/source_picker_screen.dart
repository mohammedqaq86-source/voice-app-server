import 'package:flutter/material.dart';
import 'youtube_picker_screen.dart';

class SourcePickerScreen extends StatelessWidget {
  const SourcePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sources = [
      {'name': 'YouTube', 'icon': Icons.play_circle_fill, 'active': true},
      {'name': 'X', 'icon': Icons.close, 'active': false},
      {'name': 'Netflix', 'icon': Icons.movie, 'active': false},
      {'name': 'Prime', 'icon': Icons.video_library, 'active': false},
      {'name': 'Twitch', 'icon': Icons.live_tv, 'active': false},
      {'name': 'WEB', 'icon': Icons.language, 'active': false},
      {'name': 'Playlist', 'icon': Icons.queue_music, 'active': false},
      {'name': 'History', 'icon': Icons.history, 'active': false},
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                const SizedBox(height: 18),

                const Text(
                  'voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: Colors.white, size: 32),
                      SizedBox(width: 12),
                      Text(
                        'ابحث عن فيديو أو مقطع...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 22,
                      crossAxisSpacing: 24,
                      childAspectRatio: 1.65,
                    ),
                    itemCount: sources.length,
                    itemBuilder: (context, index) {
                      final item = sources[index];

                      return InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () async {
                          if (item['active'] == true) {
                            final video = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const YoutubePickerScreen(),
                              ),
                            );

                            if (video != null) {
                              Navigator.pop(context, video);
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('هذا المصدر غير متاح حاليًا'),
                              ),
                            );
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                color: Colors.white,
                                size: 42,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item['name'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FloatingActionButton(
                    onPressed: () => Navigator.pop(context),
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: Colors.black,
                    child: const Icon(Icons.arrow_back_ios_new),
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