import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'presence_service.dart';

class SessionService with WidgetsBindingObserver {
  SessionService._();

  static final SessionService instance = SessionService._();

  StreamSubscription<User?>? _authSubscription;

  void initialize() {
    _authSubscription?.cancel();

    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await PresenceService.instance.initializePresence();
      } else {
        await PresenceService.instance.setOffline();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (FirebaseAuth.instance.currentUser != null) {
        PresenceService.instance.reconnectPresence();
      }
    } else if (state == AppLifecycleState.paused) {
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    await PresenceService.instance.dispose();
  }
}
