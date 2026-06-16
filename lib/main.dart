import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/room_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const VoiceApp());
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice App',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final RoomService _roomService = RoomService();

  // In-memory session token for the current device session
  String? _mySessionToken;
  StreamSubscription<String?>? _sessionSub;

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _startSession(User user) async {
    // Ensure user profile exists in Firestore
    await _roomService.ensureUserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );

    // Generate and save a new session token; store it in memory
    _mySessionToken = await _roomService.updateSessionToken(user.uid);

    // Listen for token changes — if another device logs in, kick this one out
    _sessionSub?.cancel();
    _sessionSub = _roomService
        .sessionTokenStream(user.uid)
        .listen((remoteToken) async {
      if (_mySessionToken == null) return;
      if (remoteToken != null &&
          remoteToken.isNotEmpty &&
          remoteToken != _mySessionToken) {
        _mySessionToken = null;
        _sessionSub?.cancel();
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تم تسجيل الدخول من جهاز آخر. تم تسجيل خروجك تلقائياً.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    });
  }

  void _stopSession() {
    _mySessionToken = null;
    _sessionSub?.cancel();
    _sessionSub = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          // Start session when user logs in (only if not already started)
          if (_mySessionToken == null) {
            _startSession(user);
          }
          return const HomeScreen();
        }

        _stopSession();
        return const LoginScreen();
      },
    );
  }
}
