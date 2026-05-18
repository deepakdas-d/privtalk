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
      print('DEBUG: createOrGetRoom called with currentUserId=$currentUserId, otherUserId=$otherUserId');
      final roomId = getRoomId(currentUserId, otherUserId);
      print('DEBUG: Generated roomId=$roomId');
      final roomRef = _firestore.collection('rooms').doc(roomId);

      print('DEBUG: Fetching document for roomId=$roomId');
      final doc = await roomRef.get();
      print('DEBUG: Document fetched. exists=${doc.exists}');
      
      if (!doc.exists) {
        print('DEBUG: Document does not exist. Creating new room...');
        await roomRef.set({
          'participants': [currentUserId, otherUserId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG: New room created successfully.');
      }

      return roomId;
    } catch (e, stackTrace) {
      print('DEBUG: Error in createOrGetRoom: $e');
      print('DEBUG: StackTrace: $stackTrace');
      rethrow;
    }
  }
}
