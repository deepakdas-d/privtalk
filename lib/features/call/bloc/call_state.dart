import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_model.dart';

abstract class CallState {}

class CallIdle extends CallState {}

class CallOutgoing extends CallState {
  final String callId;
  final String remoteUid;
  final CallType callType;
  final MediaStream? localStream;

  CallOutgoing({
    required this.callId,
    required this.remoteUid,
    required this.callType,
    this.localStream,
  });
}

class CallIncoming extends CallState {
  final CallModel call;
  CallIncoming(this.call);
}

class CallConnecting extends CallState {
  final String callId;
  final CallType callType;
  final MediaStream? localStream;

  CallConnecting({
    required this.callId,
    required this.callType,
    this.localStream,
  });
}

class CallActive extends CallState {
  final String callId;
  final CallType callType;
  final MediaStream localStream;
  final MediaStream? remoteStream;
  final bool micEnabled;
  final bool cameraEnabled;
  final Duration elapsed;

  CallActive({
    required this.callId,
    required this.callType,
    required this.localStream,
    this.remoteStream,
    this.micEnabled = true,
    this.cameraEnabled = true,
    this.elapsed = Duration.zero,
  });

  CallActive copyWith({
    MediaStream? remoteStream,
    bool? micEnabled,
    bool? cameraEnabled,
    Duration? elapsed,
  }) {
    return CallActive(
      callId: callId,
      callType: callType,
      localStream: localStream,
      remoteStream: remoteStream ?? this.remoteStream,
      micEnabled: micEnabled ?? this.micEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class CallReconnecting extends CallState {
  final String callId;
  CallReconnecting(this.callId);
}

class CallEnded extends CallState {
  final String reason; // 'hungUp', 'declined', 'missed', 'failed'
  CallEnded(this.reason);
}

class CallFailed extends CallState {
  final String reason;
  CallFailed(this.reason);
}
