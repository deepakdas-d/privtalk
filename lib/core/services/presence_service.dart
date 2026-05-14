import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  StreamSubscription? _connectionSubscription;
  String? _currentUserId;
  bool _isInitialized = false;

  Future<void> initializePresence() async {
    final user = _auth.currentUser;

    if (user == null) return;

    _currentUserId = user.uid;

    if (_isInitialized) return;

    _isInitialized = true;
    _setupPresenceListener();
  }

  void _setupPresenceListener() async {
    if (_currentUserId == null) return;

    final uid = _currentUserId!;
    final connectedRef = _db.child('.info/connected');
    final presenceRef = _db.child('presence/$uid');

    await _connectionSubscription?.cancel();

    _connectionSubscription = connectedRef.onValue.listen((event) async {
      final connected = event.snapshot.value as bool? ?? false;

      if (!connected) return;

      try {
        await presenceRef.onDisconnect().set({
          'online': false,
          'last_seen': ServerValue.timestamp,
        });

        await presenceRef.set({
          'online': true,
          'last_seen': ServerValue.timestamp,
        });
      } catch (e) {
        log('Error updating presence: $e');
      }
    });
  }

  Future<void> setOffline() async {
    final user = _auth.currentUser;

    if (user == null) return;

    try {
      await _db.child('presence/${user.uid}').set({
        'online': false,
        'last_seen': ServerValue.timestamp,
      });
    } catch (e) {
      log('Error setting offline: $e');
    }
  }

  Future<void> reconnectPresence() async {
    if (_currentUserId == null) return;

    _setupPresenceListener();
  }

  Stream<bool> userPresence(String uid) {
    return _db.child('presence/$uid/online').onValue.map((event) {
      final value = event.snapshot.value;

      return value as bool? ?? false;
    });
  }

  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    _isInitialized = false;
    _currentUserId = null;
  }
}
