import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';

class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String getRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2];
    ids.sort();
    return ids.join('_');
  }

  Future<String> createOrGetRoom(String currentUserId, String otherUserId) async {
    try {
      log('DEBUG: createOrGetRoom called with currentUserId=$currentUserId, otherUserId=$otherUserId');
      final roomId = getRoomId(currentUserId, otherUserId);
      log('DEBUG: Generated roomId=$roomId');
      final roomRef = _firestore.collection('rooms').doc(roomId);

      log('DEBUG: Fetching document for roomId=$roomId');
      final doc = await roomRef.get();
      log('DEBUG: Document fetched. exists=${doc.exists}');
      
      if (!doc.exists) {
        log('DEBUG: Document does not exist. Creating new room...');
        await roomRef.set({
          'participants': [currentUserId, otherUserId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
        log('DEBUG: New room created successfully.');
      }

      return roomId;
    } catch (e, stackTrace) {
      log('DEBUG: Error in createOrGetRoom: $e');
      log('DEBUG: StackTrace: $stackTrace');
      rethrow;
    }
  }
}
