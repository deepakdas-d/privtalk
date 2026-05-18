import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String messageId;
  final String senderId;
  final String text;
  final String type;
  final String? mediaUrl;
  final DateTime? readAt;
  final DateTime timestamp;

  MessageModel({
    required this.messageId,
    required this.senderId,
    required this.text,
    required this.type,
    this.mediaUrl,
    this.readAt,
    required this.timestamp,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      messageId: id,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      mediaUrl: map['mediaUrl'],
      readAt: (map['readAt'] as Timestamp?)?.toDate(),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'text': text,
      'type': type,
      'mediaUrl': mediaUrl,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}
