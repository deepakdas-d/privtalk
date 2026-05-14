import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/call_model.dart';

/// Single source of truth for all Firestore signaling operations.
/// Structure:
///   calls/{callId}                       — call metadata
///   calls/{callId}/callerCandidates/{id} — ICE from caller
///   calls/{callId}/receiverCandidates/{id} — ICE from receiver
class CallRepository {
  final FirebaseFirestore _firestore;

  CallRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Collection helpers ────────────────────────────────────────────────────

  DocumentReference _callDoc(String callId) =>
      _firestore.collection('calls').doc(callId);

  CollectionReference _callerCandidates(String callId) =>
      _callDoc(callId).collection('callerCandidates');

  CollectionReference _receiverCandidates(String callId) =>
      _callDoc(callId).collection('receiverCandidates');

  // ── Create call ───────────────────────────────────────────────────────────

  /// Creates the call document and writes the offer SDP.
  /// Returns the generated callId.
  Future<String> createCall({
    required String callerId,
    required String receiverId,
    required CallType type,
    required Map<String, dynamic> offer,
  }) async {
    final callId = const Uuid().v4();
    final call = CallModel(
      callId: callId,
      callerId: callerId,
      receiverId: receiverId,
      type: type,
      status: CallStatus.calling,
      offer: offer,
      createdAt: DateTime.now(),
    );
    await _callDoc(callId).set(call.toMap());
    return callId;
  }

  // ── Answer call ───────────────────────────────────────────────────────────

  Future<void> answerCall({
    required String callId,
    required Map<String, dynamic> answer,
  }) async {
    await _callDoc(
      callId,
    ).update({'answer': answer, 'status': CallStatus.connecting.value});
  }

  // ── Status updates ────────────────────────────────────────────────────────

  Future<void> updateStatus(String callId, CallStatus status) async {
    await _callDoc(callId).update({'status': status.value});
  }

  Future<void> markConnected(String callId) async {
    await _callDoc(callId).update({
      'status': CallStatus.connected.value,
      'connectedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> endCall(String callId, {required String reason}) async {
    await _callDoc(callId).update({
      'status': CallStatus.ended.value,
      'endedAt': FieldValue.serverTimestamp(),
      'endReason': reason,
    });
  }

  Future<void> declineCall(String callId) async {
    await _callDoc(callId).update({
      'status': CallStatus.declined.value,
      'endedAt': FieldValue.serverTimestamp(),
      'endReason': 'declined',
    });
  }

  Future<void> markMissed(String callId) async {
    await _callDoc(callId).update({
      'status': CallStatus.missed.value,
      'endedAt': FieldValue.serverTimestamp(),
      'endReason': 'timeout',
    });
  }

  // ── ICE candidates ────────────────────────────────────────────────────────

  /// Caller writes its own candidates here.
  Future<void> addCallerCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) async {
    await _callerCandidates(
      callId,
    ).add({...candidate, 'addedAt': FieldValue.serverTimestamp()});
  }

  /// Receiver writes its own candidates here.
  Future<void> addReceiverCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) async {
    await _receiverCandidates(
      callId,
    ).add({...candidate, 'addedAt': FieldValue.serverTimestamp()});
  }

  // ── Listeners ─────────────────────────────────────────────────────────────

  /// Caller listens to this for the answer + status changes.
  Stream<DocumentSnapshot> watchCall(String callId) =>
      _callDoc(callId).snapshots();

  /// Receiver listens here for incoming ICE candidates from caller.
  Stream<QuerySnapshot> watchCallerCandidates(String callId) =>
      _callerCandidates(callId).snapshots();

  /// Caller listens here for incoming ICE candidates from receiver.
  Stream<QuerySnapshot> watchReceiverCandidates(String callId) =>
      _receiverCandidates(callId).snapshots();

  /// Used by the app-level listener to detect incoming calls for a user.
  Stream<QuerySnapshot> watchIncomingCalls(String receiverId) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: CallStatus.calling.value)
        .snapshots();
  }
}
