import 'package:flutter/material.dart';

class YoutubeVideo {
  final String title;
  final String image;

  const YoutubeVideo({
    required this.title,
    required this.image,
  });
}

class YoutubePickerScreen extends StatelessWidget {
  const YoutubePickerScreen({super.key});

  final List<YoutubeVideo> videos = const [
    YoutubeVideo(
      title: 'جلسة طرب وسوالف',
      image: 'https://picsum.photos/400/300?random=21',
    ),
    YoutubeVideo(
      title: 'أغاني هادئة آخر الليل',
      image: 'https://picsum.photos/400/300?random=22',
    ),
    YoutubeVideo(
      title: 'مقاطع ضحك وسوالف',
      image: 'https://picsum.photos/400/300?random=23',
    ),
    YoutubeVideo(
      title: 'بث قيمرز الخليج',
      image: 'https://picsum.photos/400/300?random=24',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F8),
        appBar: AppBar(
          title: const Text(
            'اختيار فيديو من YouTube',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFF3F4F8),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];

            return InkWell(
              onTap: () {
                Navigator.pop(context, video);
              },
              child: Container(
                height: 118,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    SizedBox(
                      width: 136,
                      height: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(video.image, fit: BoxFit.cover),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 46,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
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