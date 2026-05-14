import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }

enum CallStatus {
  idle,
  calling,
  incoming,
  ringing,
  connecting,
  connected,
  reconnecting,
  ended,
  declined,
  missed,
  failed,
}

extension CallStatusX on CallStatus {
  String get value => name; // 'calling', 'connected', etc.

  static CallStatus fromString(String s) => CallStatus.values.firstWhere(
    (e) => e.name == s,
    orElse: () => CallStatus.ended,
  );
}

class CallModel {
  final String callId;
  final String callerId;
  final String receiverId;
  final CallType type;
  final CallStatus status;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final String? endReason;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.type,
    required this.status,
    this.offer,
    this.answer,
    required this.createdAt,
    this.connectedAt,
    this.endedAt,
    this.endReason,
  });

  bool get isVideo => type == CallType.video;

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['callId'] as String,
      callerId: map['callerId'] as String,
      receiverId: map['receiverId'] as String,
      type: (map['type'] as String) == 'video'
          ? CallType.video
          : CallType.audio,
      status: CallStatusX.fromString(map['status'] as String),
      offer: map['offer'] as Map<String, dynamic>?,
      answer: map['answer'] as Map<String, dynamic>?,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      connectedAt: map['connectedAt'] != null
          ? (map['connectedAt'] as Timestamp).toDate()
          : null,
      endedAt: map['endedAt'] != null
          ? (map['endedAt'] as Timestamp).toDate()
          : null,
      endReason: map['endReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'receiverId': receiverId,
      'type': type.name,
      'status': status.value,
      if (offer != null) 'offer': offer,
      if (answer != null) 'answer': answer,
      'createdAt': Timestamp.fromDate(createdAt),
      if (connectedAt != null) 'connectedAt': Timestamp.fromDate(connectedAt!),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
      if (endReason != null) 'endReason': endReason,
    };
  }

  CallModel copyWith({
    CallStatus? status,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
    DateTime? connectedAt,
    DateTime? endedAt,
    String? endReason,
  }) {
    return CallModel(
      callId: callId,
      callerId: callerId,
      receiverId: receiverId,
      type: type,
      status: status ?? this.status,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
    );
  }
}
