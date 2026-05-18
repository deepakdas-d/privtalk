import 'package:cloud_firestore/cloud_firestore.dart';

class RoomModel {
  final String roomId;
  final List<String> participants;
  final DateTime createdAt;
  final String lastMessage;
  final DateTime lastMessageAt;

  RoomModel({
    required this.roomId,
    required this.participants,
    required this.createdAt,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  factory RoomModel.fromMap(Map<String, dynamic> map, String id) {
    return RoomModel(
      roomId: id,
      participants: List<String>.from(map['participants'] ?? []),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageAt: (map['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
  }
}
