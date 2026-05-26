import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import '../models/message_model.dart';
import '../../../core/services/fcm_sender_service.dart';

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
    required String receiverId,
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

    // ─── Trigger FCM text message notification ─────────────────────────────────
    if (senderId == receiverId) return; // Don't notify oneself
    if (text.trim().isEmpty) return; // Avoid empty push

    try {
      final senderDoc = await _firestore
          .collection('users')
          .doc(senderId)
          .get();
      final receiverDoc = await _firestore
          .collection('users')
          .doc(receiverId)
          .get();

      final senderName = senderDoc.data()?['name'] ?? 'Someone';
      final receiverToken = receiverDoc.data()?['fcmToken'];

      if (receiverToken != null && receiverToken.toString().isNotEmpty) {
        await FcmSenderService.sendTextMessage(
          receiverFcmToken: receiverToken,
          senderName: senderName,
          senderId: senderId,
          messageText: text,
          chatId: roomId,
        );
      }
    } catch (e) {
      developer.log(
        'Failed to send text message FCM: $e',
        name: 'MessageService',
      );
    }
  }
}
