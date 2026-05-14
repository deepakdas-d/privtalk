import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_model.dart';

abstract class CallEvent {}

// ── Outgoing ──────────────────────────────────────────────────────────────

class StartCallEvent extends CallEvent {
  final String callerId;
  final String receiverId;
  final CallType callType;

  StartCallEvent({
    required this.callerId,
    required this.receiverId,
    required this.callType,
  });
}

// ── Incoming ──────────────────────────────────────────────────────────────

class IncomingCallEvent extends CallEvent {
  final CallModel call;
  IncomingCallEvent(this.call);
}

class AcceptCallEvent extends CallEvent {
  final CallModel call;
  AcceptCallEvent(this.call);
}

class DeclineCallEvent extends CallEvent {
  final String callId;
  DeclineCallEvent(this.callId);
}

// ── Signaling ─────────────────────────────────────────────────────────────

/// Fired when Firestore delivers the remote answer (caller side).
class RemoteAnswerReceivedEvent extends CallEvent {
  final Map<String, dynamic> answer;
  RemoteAnswerReceivedEvent(this.answer);
}

/// Fired for each new ICE candidate from the remote peer.
class RemoteIceCandidateEvent extends CallEvent {
  final Map<String, dynamic> candidate;
  RemoteIceCandidateEvent(this.candidate);
}

/// Fired by WebRtcService when we have a local ICE candidate to send.
class LocalIceCandidateEvent extends CallEvent {
  final RTCIceCandidate candidate;
  LocalIceCandidateEvent(this.candidate);
}

// ── Connection state ──────────────────────────────────────────────────────

class ConnectionStateChangedEvent extends CallEvent {
  final RTCPeerConnectionState state;
  ConnectionStateChangedEvent(this.state);
}

// ── Controls ─────────────────────────────────────────────────────────────

class ToggleMicEvent extends CallEvent {
  final bool enabled;
  ToggleMicEvent(this.enabled);
}

class ToggleCameraEvent extends CallEvent {
  final bool enabled;
  ToggleCameraEvent(this.enabled);
}

class SwitchCameraEvent extends CallEvent {}

class EndCallEvent extends CallEvent {
  final String callId;
  EndCallEvent(this.callId);
}

// ── Timeout ───────────────────────────────────────────────────────────────

class CallTimeoutEvent extends CallEvent {
  final String callId;
  CallTimeoutEvent(this.callId);
}

// ── Remote state changes ──────────────────────────────────────────────────

class RemoteStreamReceivedEvent extends CallEvent {
  final MediaStream stream;
  RemoteStreamReceivedEvent(this.stream);
}

class CallRemotelyDeclinedEvent extends CallEvent {}

class CallRemotelyEndedEvent extends CallEvent {
  final String reason;
  CallRemotelyEndedEvent(this.reason);
}
