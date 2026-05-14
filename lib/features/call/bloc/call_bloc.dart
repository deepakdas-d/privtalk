import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call_model.dart';
import '../repository/call_repository.dart';
import '../services/webrtc_service.dart';
import 'call_event.dart';
import 'call_state.dart';

class CallBloc extends Bloc<CallEvent, CallState> {
  final CallRepository _repository;
  final WebRtcService _webrtc;

  // Firestore subscriptions
  StreamSubscription? _callWatcher;
  StreamSubscription? _remoteIceWatcher;

  // Timeout timer (45 s for outgoing calls)
  Timer? _timeoutTimer;

  // Duration ticker for active calls
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;

  // Track which ICE candidates we have already processed (by Firestore doc ID)
  final Set<String> _processedCandidateIds = {};

  // Whether we are the caller or receiver — needed to know which sub-collection
  // to write our local candidates into.
  bool _isCaller = false;
  String? _currentCallId;

  CallBloc({required CallRepository repository, WebRtcService? webrtc})
    : _repository = repository,
      _webrtc = webrtc ?? WebRtcService(),
      super(CallIdle()) {
    on<StartCallEvent>(_onStartCall);
    on<AcceptCallEvent>(_onAcceptCall);
    on<DeclineCallEvent>(_onDeclineCall);
    on<EndCallEvent>(_onEndCall);
    on<RemoteAnswerReceivedEvent>(_onRemoteAnswer);
    on<RemoteIceCandidateEvent>(_onRemoteIceCandidate);
    on<LocalIceCandidateEvent>(_onLocalIceCandidate);
    on<ConnectionStateChangedEvent>(_onConnectionStateChanged);
    on<ToggleMicEvent>(_onToggleMic);
    on<ToggleCameraEvent>(_onToggleCamera);
    on<SwitchCameraEvent>(_onSwitchCamera);
    on<CallTimeoutEvent>(_onCallTimeout);
    on<IncomingCallEvent>(_onIncoming);
    on<RemoteStreamReceivedEvent>(_onRemoteStreamReceived);
    on<CallRemotelyDeclinedEvent>(_onCallRemotelyDeclined);
    on<CallRemotelyEndedEvent>(_onCallRemotelyEnded);
  }

  // ── WebRTC callback wiring ─────────────────────────────────────────────

  void _wireWebRtcCallbacks() {
    _webrtc.onIceCandidate = (candidate) {
      if (!isClosed) add(LocalIceCandidateEvent(candidate));
    };

    _webrtc.onConnectionStateChange = (state) {
      if (!isClosed) add(ConnectionStateChangedEvent(state));
    };

    _webrtc.onRemoteStream = (stream) {
      if (!isClosed) add(RemoteStreamReceivedEvent(stream));
    };
  }

  // ── START CALL (Caller) ────────────────────────────────────────────────

  Future<void> _onStartCall(
    StartCallEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      _isCaller = true;
      await _webrtc.initialize(isVideo: event.callType == CallType.video);
      _wireWebRtcCallbacks();

      final offer = await _webrtc.createOffer();
      final offerMap = {'type': offer.type, 'sdp': offer.sdp};

      final callId = await _repository.createCall(
        callerId: event.callerId,
        receiverId: event.receiverId,
        type: event.callType,
        offer: offerMap,
      );

      _currentCallId = callId;

      emit(
        CallOutgoing(
          callId: callId,
          remoteUid: event.receiverId,
          callType: event.callType,
          localStream: _webrtc.localStream,
        ),
      );

      // 45-second timeout
      _timeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!isClosed) add(CallTimeoutEvent(callId));
      });

      // Watch for answer + status changes
      _listenToCallDocument(callId);

      // Watch for receiver's ICE candidates
      _listenToRemoteCandidates(callId, isCaller: true);
    } catch (e) {
      emit(CallFailed('Failed to start call: $e'));
      await _cleanup();
    }
  }

  // ── INCOMING (received from app-level listener) ────────────────────────

  Future<void> _onIncoming(
    IncomingCallEvent event,
    Emitter<CallState> emit,
  ) async {
    emit(CallIncoming(event.call));
  }

  // ── ACCEPT CALL (Receiver) ─────────────────────────────────────────────

  Future<void> _onAcceptCall(
    AcceptCallEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      _isCaller = false;
      _currentCallId = event.call.callId;
      _processedCandidateIds.clear();

      await _webrtc.initialize(isVideo: event.call.isVideo);
      _wireWebRtcCallbacks();

      // Set remote description (offer from caller)
      await _webrtc.setRemoteDescription(event.call.offer!);

      final answer = await _webrtc.createAnswer();
      final answerMap = {'type': answer.type, 'sdp': answer.sdp};

      await _repository.answerCall(
        callId: event.call.callId,
        answer: answerMap,
      );

      emit(
        CallConnecting(
          callId: event.call.callId,
          callType: event.call.type,
          localStream: _webrtc.localStream,
        ),
      );

      // Receiver watches caller's ICE candidates
      _listenToRemoteCandidates(event.call.callId, isCaller: false);
    } catch (e) {
      emit(CallFailed('Failed to accept call: $e'));
      await _cleanup();
    }
  }

  // ── DECLINE CALL ───────────────────────────────────────────────────────

  Future<void> _onDeclineCall(
    DeclineCallEvent event,
    Emitter<CallState> emit,
  ) async {
    await _repository.declineCall(event.callId);
    emit(CallEnded('declined'));
    await _cleanup();
  }

  // ── END CALL ───────────────────────────────────────────────────────────

  Future<void> _onEndCall(EndCallEvent event, Emitter<CallState> emit) async {
    await _repository.endCall(event.callId, reason: 'hungUp');
    emit(CallEnded('hungUp'));
    await _cleanup();
  }

  // ── REMOTE ANSWER (Caller side) ────────────────────────────────────────

  Future<void> _onRemoteAnswer(
    RemoteAnswerReceivedEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      await _webrtc.setRemoteDescription(event.answer);
      if (_currentCallId != null) {
        emit(
          CallConnecting(
            callId: _currentCallId!,
            callType: _callTypeFromState(),
            localStream: _webrtc.localStream,
          ),
        );
      }
    } catch (e) {
      emit(CallFailed('SDP error: $e'));
      await _cleanup();
    }
  }

  // ── REMOTE ICE CANDIDATE ───────────────────────────────────────────────

  Future<void> _onRemoteIceCandidate(
    RemoteIceCandidateEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      await _webrtc.addRemoteCandidate(event.candidate);
    } catch (_) {
      // Non-fatal: bad candidate, just skip
    }
  }

  // ── LOCAL ICE CANDIDATE ────────────────────────────────────────────────

  Future<void> _onLocalIceCandidate(
    LocalIceCandidateEvent event,
    Emitter<CallState> emit,
  ) async {
    if (_currentCallId == null) return;

    final candidateMap = {
      'candidate': event.candidate.candidate,
      'sdpMid': event.candidate.sdpMid,
      'sdpMLineIndex': event.candidate.sdpMLineIndex,
    };

    if (_isCaller) {
      await _repository.addCallerCandidate(_currentCallId!, candidateMap);
    } else {
      await _repository.addReceiverCandidate(_currentCallId!, candidateMap);
    }
  }

  // ── CONNECTION STATE CHANGED ───────────────────────────────────────────

  Future<void> _onConnectionStateChanged(
    ConnectionStateChangedEvent event,
    Emitter<CallState> emit,
  ) async {
    switch (event.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _timeoutTimer?.cancel();
        if (_currentCallId != null) {
          await _repository.markConnected(_currentCallId!);
        }
        _startDurationTimer(emit);
        emit(
          CallActive(
            callId: _currentCallId ?? '',
            callType: _callTypeFromState(),
            localStream: _webrtc.localStream!,
            remoteStream: _webrtc.remoteStream,
          ),
        );

      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (state is CallActive && _currentCallId != null) {
          emit(CallReconnecting(_currentCallId!));
        }

      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (_currentCallId != null) {
          await _repository.endCall(_currentCallId!, reason: 'failed');
        }
        emit(CallFailed('iceFailure'));
        await _cleanup();

      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        // Already cleaned up via EndCallEvent
        break;

      default:
        break;
    }
  }

  // ── TOGGLE MIC ─────────────────────────────────────────────────────────

  void _onToggleMic(ToggleMicEvent event, Emitter<CallState> emit) {
    _webrtc.toggleMic(enabled: event.enabled);
    if (state is CallActive) {
      emit((state as CallActive).copyWith(micEnabled: event.enabled));
    }
  }

  // ── TOGGLE CAMERA ──────────────────────────────────────────────────────

  void _onToggleCamera(ToggleCameraEvent event, Emitter<CallState> emit) {
    _webrtc.toggleCamera(enabled: event.enabled);
    if (state is CallActive) {
      emit((state as CallActive).copyWith(cameraEnabled: event.enabled));
    }
  }

  // ── SWITCH CAMERA ──────────────────────────────────────────────────────

  Future<void> _onSwitchCamera(
    SwitchCameraEvent event,
    Emitter<CallState> emit,
  ) async {
    await _webrtc.switchCamera();
  }

  // ── TIMEOUT ────────────────────────────────────────────────────────────

  Future<void> _onCallTimeout(
    CallTimeoutEvent event,
    Emitter<CallState> emit,
  ) async {
    await _repository.markMissed(event.callId);
    emit(CallEnded('missed'));
    await _cleanup();
  }

  // ── REMOTE STREAM RECEIVED ─────────────────────────────────────────

  void _onRemoteStreamReceived(
    RemoteStreamReceivedEvent event,
    Emitter<CallState> emit,
  ) {
    if (state is CallActive) {
      emit((state as CallActive).copyWith(remoteStream: event.stream));
    }
  }

  // ── CALL REMOTELY DECLINED ─────────────────────────────────────────

  Future<void> _onCallRemotelyDeclined(
    CallRemotelyDeclinedEvent event,
    Emitter<CallState> emit,
  ) async {
    emit(CallEnded('declined'));
    await _cleanup();
  }

  // ── CALL REMOTELY ENDED ────────────────────────────────────────────

  Future<void> _onCallRemotelyEnded(
    CallRemotelyEndedEvent event,
    Emitter<CallState> emit,
  ) async {
    emit(CallEnded(event.reason));
    await _cleanup();
  }

  // ── Firestore listeners ────────────────────────────────────────────────

  void _listenToCallDocument(String callId) {
    _callWatcher?.cancel();
    _callWatcher = _repository.watchCall(callId).listen((snap) {
      if (!snap.exists || isClosed) return;
      final data = snap.data() as Map<String, dynamic>;
      final status = CallStatusX.fromString(data['status'] as String? ?? '');

      switch (status) {
        case CallStatus.connecting:
          final answer = data['answer'] as Map<String, dynamic>?;
          if (answer != null && _isCaller) {
            add(RemoteAnswerReceivedEvent(answer));
          }

        case CallStatus.declined:
          if (!isClosed) {
            add(CallRemotelyDeclinedEvent());
          }

        case CallStatus.ended:
          if (!isClosed && state is! CallEnded) {
            add(CallRemotelyEndedEvent(data['endReason'] as String? ?? 'hungUp'));
          }

        default:
          break;
      }
    });
  }

  void _listenToRemoteCandidates(String callId, {required bool isCaller}) {
    _remoteIceWatcher?.cancel();

    // Caller listens to receiver's candidates; receiver listens to caller's.
    final stream = isCaller
        ? _repository.watchReceiverCandidates(callId)
        : _repository.watchCallerCandidates(callId);

    _remoteIceWatcher = stream.listen((snap) {
      if (isClosed) return;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final id = change.doc.id;
          if (_processedCandidateIds.contains(id)) continue;
          _processedCandidateIds.add(id);

          final data = change.doc.data() as Map<String, dynamic>;
          add(RemoteIceCandidateEvent(data));
        }
      }
    });
  }

  // ── Duration timer ─────────────────────────────────────────────────────

  void _startDurationTimer(Emitter<CallState> emit) {
    _durationTimer?.cancel();
    _elapsed = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      _elapsed += const Duration(seconds: 1);
      if (state is CallActive) {
        emit((state as CallActive).copyWith(elapsed: _elapsed));
      }
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  CallType _callTypeFromState() {
    final s = state;
    if (s is CallOutgoing) return s.callType;
    if (s is CallConnecting) return s.callType;
    if (s is CallActive) return s.callType;
    return CallType.audio;
  }

  Future<void> _cleanup() async {
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _callWatcher?.cancel();
    _remoteIceWatcher?.cancel();
    _processedCandidateIds.clear();
    _currentCallId = null;
    await _webrtc.dispose();
  }

  @override
  Future<void> close() async {
    log('CALL BLOC CLOSED');
    await _cleanup();
    return super.close();
  }
}
