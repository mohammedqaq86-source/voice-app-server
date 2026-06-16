import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
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

  String? _mySessionToken;
  StreamSubscription<String?>? _sessionSub;

  // Track which user's session is active to prevent duplicate _startSession calls
  String? _lastUserId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _startSession(User user) async {
    await _roomService.ensureUserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );

    _mySessionToken = await _roomService.updateSessionToken(user.uid);

    _sessionSub?.cancel();
    _sessionSub = _roomService.sessionTokenStream(user.uid).listen((remoteToken) async {
      if (_mySessionToken == null) return;
      if (remoteToken != null &&
          remoteToken.isNotEmpty &&
          remoteToken != _mySessionToken) {
        // Another device logged in — kick this session out
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
    _lastUserId = null;
    _profileStream = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;

        if (user != null) {
          // New user or re-login — set up session and profile stream once
          if (_lastUserId != user.uid) {
            _lastUserId = user.uid;
            _mySessionToken = null;
            _profileStream = _roomService.userProfileStream(user.uid);
            _startSession(user); // fire-and-forget; session runs in background
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _profileStream,
            builder: (context, profileSnap) {
              if (profileSnap.connectionState == ConnectionState.waiting) {
                return const _LoadingScreen();
              }

              final data = profileSnap.data?.data() ?? {};
              final username = (data['username'] ?? '').toString().trim();

              // Enforce onboarding until username is set
              if (username.isEmpty) {
                return const OnboardingScreen();
              }

              return const HomeScreen();
            },
          );
        }

        _stopSession();
        return const LoginScreen();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF120B2E),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF7B3FE4)),
      ),
    );
  }
}
