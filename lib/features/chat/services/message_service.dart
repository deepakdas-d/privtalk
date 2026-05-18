import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<MessageModel>> getMessagesStream(String roomId) {
    return _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String text,
    String type = 'text',
  }) async {
    final messageRef = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    final messageData = {
      'senderId': senderId,
      'text': text,
      'type': type,
      'mediaUrl': null,
      'readAt': null,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final roomData = {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };

    // Use a batch to update both message and room
    final batch = _firestore.batch();
    batch.set(messageRef, messageData);
    
    final roomRef = _firestore.collection('rooms').doc(roomId);
    batch.update(roomRef, roomData);

    await batch.commit();
  }
}
