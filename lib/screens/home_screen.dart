import 'package:flutter/material.dart';
import '../models/room.dart';
import '../widgets/room_card.dart';
import '../widgets/search_box.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Room> rooms = [
    const Room(
      title: 'سوالف ووناسة',
      image: 'https://picsum.photos/400/300?random=1',
      users: 94,
      speakers: 7,
      hasYoutube: true,
    ),
    const Room(
      title: 'جلسة آخر الليل',
      image: 'https://picsum.photos/400/300?random=2',
      users: 76,
      speakers: 5,
      hasYoutube: true,
    ),
    const Room(
      title: 'قيمرز الخليج',
      image: 'https://picsum.photos/400/300?random=3',
      users: 52,
      speakers: 4,
      hasYoutube: false,
    ),
    const Room(
      title: 'أغاني وسوالف',
      image: 'https://picsum.photos/400/300?random=4',
      users: 41,
      speakers: 3,
      hasYoutube: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F8),

        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF5865F2),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),

          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFFF3F4F8),
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              builder: (sheetContext) {
                return CreateRoomSheet(
                  onCreate: () {
                    const newRoom = Room(
                      title: 'روم جديد',
                      image:
                          'https://picsum.photos/400/300?random=99',
                      users: 1,
                      speakers: 1,
                      hasYoutube: true,
                    );

                    setState(() {
                      rooms.insert(0, newRoom);
                    });

                    Navigator.pop(sheetContext);

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomScreen(room: newRoom),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),

        body: SafeArea(
          child: Column(
            children: [
              const HomeHeader(),
              const SearchBox(),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    return RoomCard(room: rooms[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu_rounded, size: 32),
          ),

          const Spacer(),

          const Text(
            'الرومات العامة',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),

          const Spacer(),

          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.people_alt_rounded, size: 32),
          ),
        ],
      ),
    );
  }
}

class CreateRoomSheet extends StatelessWidget {
  const CreateRoomSheet({
    super.key,
    required this.onCreate,
  });

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'إنشاء روم',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5865F2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'روم عام',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'روم خاص',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 26),

          Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 34,
                ),

                SizedBox(width: 12),

                Text(
                  'اختيار فيديو من YouTube',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),

          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: onCreate,

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),

              child: const Text(
                'إنشاء الروم',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}