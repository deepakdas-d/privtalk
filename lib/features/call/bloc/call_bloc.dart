import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/permission_service.dart';
import '../models/call_model.dart';
import '../repository/call_repository.dart';
import '../services/webrtc_service.dart';
import 'call_event.dart';
import 'call_state.dart';

final _log = log;

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
      _log('📞 [CALLER] ========== STARTING OUTGOING CALL ==========', name: 'CallBloc.StartCall');
      _log('📞 [CALLER] Target: ${event.receiverId} | Type: ${event.callType} | Caller: ${event.callerId}', name: 'CallBloc.StartCall');

      _isCaller = true;

      // Request permissions for video calls
      if (event.callType == CallType.video) {
        _log('📞 [CALLER] Requesting camera & mic permissions', name: 'CallBloc.StartCall');
        final hasPermissions = await PermissionService.requestCameraAndMic();
        if (!hasPermissions) {
          _log('❌ [CALLER] Permission denied', name: 'CallBloc.StartCall');
          emit(CallFailed('Camera or microphone permission denied'));
          return;
        }
        _log('✅ [CALLER] Permissions granted', name: 'CallBloc.StartCall');
      }

      _log('📞 [CALLER] Initializing WebRTC (isVideo=${event.callType == CallType.video})', name: 'CallBloc.StartCall');
      await _webrtc.initialize(isVideo: event.callType == CallType.video);

      // Set callId BEFORE wiring callbacks and creating offer
      // This ensures ICE candidates are captured when they fire during setLocalDescription
      _currentCallId = const Uuid().v4();
      _log('📞 [CALLER] Generated callId=$_currentCallId (will update with Firestore doc)', name: 'CallBloc.StartCall');

      _wireWebRtcCallbacks();

      _log('📞 [CALLER] Creating offer...', name: 'CallBloc.StartCall');
      final offer = await _webrtc.createOffer();
      final offerMap = {'type': offer.type, 'sdp': offer.sdp};

      _log('📞 [CALLER] Storing call in Firestore', name: 'CallBloc.StartCall');
      final firestoreCallId = await _repository.createCall(
        callerId: event.callerId,
        receiverId: event.receiverId,
        type: event.callType,
        offer: offerMap,
      );

      // Update with actual Firestore callId if different
      if (firestoreCallId != _currentCallId) {
        _log('📞 [CALLER] Updated callId to Firestore value: $firestoreCallId', name: 'CallBloc.StartCall');
        _currentCallId = firestoreCallId;
      }

      _log('📞 [CALLER] ✅ Call created | callId=$_currentCallId', name: 'CallBloc.StartCall');

      emit(
        CallOutgoing(
          callId: _currentCallId!,
          remoteUid: event.receiverId,
          callType: event.callType,
          localStream: _webrtc.localStream,
        ),
      );

      // 45-second timeout
      _timeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!isClosed) add(CallTimeoutEvent(_currentCallId!));
      });

      _log('📞 [CALLER] Starting call document watcher', name: 'CallBloc.StartCall');
      // Watch for answer + status changes
      _listenToCallDocument(_currentCallId!);

      _log('📞 [CALLER] Starting ICE candidate watcher (receiving from receiver)', name: 'CallBloc.StartCall');
      // Watch for receiver's ICE candidates
      _listenToRemoteCandidates(_currentCallId!, isCaller: true);

      _log('📞 [CALLER] ========== CALL INITIATED - AWAITING ANSWER ==========', name: 'CallBloc.StartCall');
    } catch (e) {
      _log('❌ [CALLER] Error: $e', name: 'CallBloc.StartCall');
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
      _log('📱 [RECEIVER] ========== ACCEPTING INCOMING CALL ==========', name: 'CallBloc.AcceptCall');
      _log('📱 [RECEIVER] From: ${event.call.callerId} | Type: ${event.call.type} | callId=${event.call.callId}', name: 'CallBloc.AcceptCall');

      _isCaller = false;
      _currentCallId = event.call.callId;
      _processedCandidateIds.clear();

      // Request permissions for video calls
      if (event.call.isVideo) {
        _log('📱 [RECEIVER] Requesting camera & mic permissions', name: 'CallBloc.AcceptCall');
        final hasPermissions = await PermissionService.requestCameraAndMic();
        if (!hasPermissions) {
          _log('❌ [RECEIVER] Permission denied', name: 'CallBloc.AcceptCall');
          emit(CallFailed('Camera or microphone permission denied'));
          await _repository.declineCall(event.call.callId);
          return;
        }
        _log('✅ [RECEIVER] Permissions granted', name: 'CallBloc.AcceptCall');
      }

      _log('📱 [RECEIVER] Initializing WebRTC (isVideo=${event.call.isVideo})', name: 'CallBloc.AcceptCall');
      await _webrtc.initialize(isVideo: event.call.isVideo);
      _wireWebRtcCallbacks();

      _log('📱 [RECEIVER] Starting ICE candidate watcher (receiving from caller)', name: 'CallBloc.AcceptCall');
      // ── Set up ICE listener BEFORE creating answer ──
      _listenToRemoteCandidates(event.call.callId, isCaller: false);

      _log('📱 [RECEIVER] Setting remote description (offer from caller) | sdp_len=${event.call.offer?['sdp'].toString().length}', name: 'CallBloc.AcceptCall');
      // Set remote description (offer from caller)
      await _webrtc.setRemoteDescription(event.call.offer!);

      _log('📱 [RECEIVER] Creating answer...', name: 'CallBloc.AcceptCall');
      final answer = await _webrtc.createAnswer();
      final answerMap = {'type': answer.type, 'sdp': answer.sdp};

      _log('📱 [RECEIVER] Storing answer in Firestore', name: 'CallBloc.AcceptCall');
      await _repository.answerCall(
        callId: event.call.callId,
        answer: answerMap,
      );

      _log('📱 [RECEIVER] ✅ Answer sent | callId=${event.call.callId}', name: 'CallBloc.AcceptCall');

      emit(
        CallConnecting(
          callId: event.call.callId,
          callType: event.call.type,
          localStream: _webrtc.localStream,
        ),
      );

      _log('📱 [RECEIVER] ========== HANDSHAKE COMPLETE - AWAITING ICE CANDIDATES ==========', name: 'CallBloc.AcceptCall');
    } catch (e) {
      _log('❌ [RECEIVER] Error: $e', name: 'CallBloc.AcceptCall');
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
    final callId = event.callId.isNotEmpty ? event.callId : _currentCallId;
    if (callId == null || callId.isEmpty) {
      _log('❌ [END CALL] No callId available', name: 'CallBloc.EndCall');
      emit(CallEnded('hungUp'));
      await _cleanup();
      return;
    }
    try {
      await _repository.endCall(callId, reason: 'hungUp');
    } catch (e) {
      _log('❌ [END CALL] Error updating Firestore: $e', name: 'CallBloc.EndCall');
    }
    emit(CallEnded('hungUp'));
    await _cleanup();
  }

  // ── REMOTE ANSWER (Caller side) ────────────────────────────────────────

  Future<void> _onRemoteAnswer(
    RemoteAnswerReceivedEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      _log('🤝 [CALLER] ========== ANSWER RECEIVED ==========', name: 'CallBloc.RemoteAnswer');
      _log('🤝 [CALLER] Setting remote description (answer from receiver) | type=${event.answer['type']} | sdp_len=${(event.answer['sdp'] as String?)?.length}', name: 'CallBloc.RemoteAnswer');
      await _webrtc.setRemoteDescription(event.answer);
      _log('🤝 [CALLER] ✅ Remote description set - HANDSHAKE COMPLETE', name: 'CallBloc.RemoteAnswer');

      if (_currentCallId != null) {
        emit(
          CallConnecting(
            callId: _currentCallId!,
            callType: _callTypeFromState(),
            localStream: _webrtc.localStream,
          ),
        );
        _log('🤝 [CALLER] State -> CallConnecting | Awaiting ICE candidates', name: 'CallBloc.RemoteAnswer');
      }
    } catch (e) {
      _log('❌ [CALLER] SDP error: $e', name: 'CallBloc.RemoteAnswer');
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
      final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
      _log('$role Adding remote ICE candidate | candidate=${event.candidate['candidate'].toString().substring(0, 40)}... | mid=${event.candidate['sdpMid']}', name: 'CallBloc.IceCandidate');
      await _webrtc.addRemoteCandidate(event.candidate);
      _log('$role ✅ Remote ICE candidate added', name: 'CallBloc.IceCandidate');
    } catch (e) {
      final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
      _log('$role ⚠️ Failed to add ICE candidate (non-fatal): $e', name: 'CallBloc.IceCandidate');
      // Non-fatal: bad candidate, just skip
    }
  }

  // ── LOCAL ICE CANDIDATE ────────────────────────────────────────────────

  Future<void> _onLocalIceCandidate(
    LocalIceCandidateEvent event,
    Emitter<CallState> emit,
  ) async {
    if (_currentCallId == null) return;

    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    _log('$role Uploading local ICE candidate | candidate=${event.candidate.candidate?.substring(0, 40)}... | mid=${event.candidate.sdpMid}', name: 'CallBloc.IceCandidate');

    final candidateMap = {
      'candidate': event.candidate.candidate,
      'sdpMid': event.candidate.sdpMid,
      'sdpMLineIndex': event.candidate.sdpMLineIndex,
    };

    if (_isCaller) {
      await _repository.addCallerCandidate(_currentCallId!, candidateMap);
      _log('$role ✅ Caller ICE candidate uploaded to Firestore', name: 'CallBloc.IceCandidate');
    } else {
      await _repository.addReceiverCandidate(_currentCallId!, candidateMap);
      _log('$role ✅ Receiver ICE candidate uploaded to Firestore', name: 'CallBloc.IceCandidate');
    }
  }

  // ── CONNECTION STATE CHANGED ───────────────────────────────────────────

  Future<void> _onConnectionStateChanged(
    ConnectionStateChangedEvent event,
    Emitter<CallState> emit,
  ) async {
    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    _log('$role 🔄 Connection state: $event.state', name: 'CallBloc.Connection');

    switch (event.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _log('$role 🎉 ========== PEER CONNECTION ESTABLISHED ==========', name: 'CallBloc.Connection');
        _timeoutTimer?.cancel();
        if (_currentCallId != null) {
          _log('$role Marking call as connected in Firestore', name: 'CallBloc.Connection');
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
        _log('$role ✅ State -> CallActive', name: 'CallBloc.Connection');

      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _log('$role ⚠️ Peer connection disconnected', name: 'CallBloc.Connection');
        if (state is CallActive && _currentCallId != null) {
          _log('$role State -> CallReconnecting', name: 'CallBloc.Connection');
          emit(CallReconnecting(_currentCallId!));
        }

      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _log('$role ❌ ========== PEER CONNECTION FAILED ==========', name: 'CallBloc.Connection');
        if (_currentCallId != null) {
          await _repository.endCall(_currentCallId!, reason: 'failed');
        }
        emit(CallFailed('iceFailure'));
        await _cleanup();

      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _log('$role Connection closed', name: 'CallBloc.Connection');
        // Already cleaned up via EndCallEvent
        break;

      default:
        _log('$role State: ${event.state}', name: 'CallBloc.Connection');
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
    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    _log('$role 📡 ========== REMOTE STREAM RECEIVED ==========', name: 'CallBloc.RemoteStream');
    _log('$role Remote stream tracks: video=${event.stream.getVideoTracks().length}, audio=${event.stream.getAudioTracks().length}', name: 'CallBloc.RemoteStream');

    // Update remote stream regardless of state (it may arrive during CallConnecting)
    final currentState = state;
    if (currentState is CallActive) {
      _log('$role Updating CallActive state with remote stream', name: 'CallBloc.RemoteStream');
      emit((currentState).copyWith(remoteStream: event.stream));
    } else if (currentState is CallConnecting) {
      _log('$role Remote stream arrived during CallConnecting (will be picked up on transition to CallActive)', name: 'CallBloc.RemoteStream');
      // If still connecting and remote stream arrives, update internal reference
      // It will be picked up when state transitions to CallActive
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
    _log('📡 [CALLER] Subscribing to call document for remote answer/status', name: 'CallBloc.Firestore');
    _callWatcher?.cancel();
    _callWatcher = _repository.watchCall(callId).listen((snap) {
      if (!snap.exists || isClosed) return;
      final data = snap.data() as Map<String, dynamic>;
      final status = CallStatusX.fromString(data['status'] as String? ?? '');

      _log('📡 [CALLER] Call status: $status', name: 'CallBloc.Firestore');

      switch (status) {
        case CallStatus.connecting:
          final answer = data['answer'] as Map<String, dynamic>?;
          if (answer != null && _isCaller) {
            _log('📡 [CALLER] ✅ Answer received from receiver', name: 'CallBloc.Firestore');
            add(RemoteAnswerReceivedEvent(answer));
          }

        case CallStatus.declined:
          _log('📡 [CALLER] ❌ Call declined by receiver', name: 'CallBloc.Firestore');
          if (!isClosed) {
            add(CallRemotelyDeclinedEvent());
          }

        case CallStatus.ended:
          _log('📡 [CALLER] Call ended by receiver', name: 'CallBloc.Firestore');
          if (!isClosed && state is! CallEnded) {
            add(CallRemotelyEndedEvent(data['endReason'] as String? ?? 'hungUp'));
          }

        default:
          break;
      }
    });
  }

  void _listenToRemoteCandidates(String callId, {required bool isCaller}) {
    final role = isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    _log('$role Subscribing to ICE candidates from ${isCaller ? "receiver" : "caller"}', name: 'CallBloc.Firestore');

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
          _log('$role 📡 New ICE candidate: ${data['candidate'].toString().substring(0, 40)}... | mid=${data['sdpMid']}', name: 'CallBloc.Firestore');
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
    _log('🛑 ========== CALL BLOC CLOSED ==========', name: 'CallBloc.Cleanup');
    await _cleanup();
    return super.close();
  }
}
