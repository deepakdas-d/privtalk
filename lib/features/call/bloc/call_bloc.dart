import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/services/permission_service.dart';
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

  // Whether we are the caller or receiver
  bool _isCaller = false;

  // The confirmed Firestore callId — null until Firestore doc is created
  String? _currentCallId;

  // ─────────────────────────────────────────────────────────────────────────
  // ICE CANDIDATE BUFFER — holds candidates that fire BEFORE _currentCallId
  // is assigned. Flushed immediately once _currentCallId is confirmed.
  // This is the fix for the race condition where web ICE candidates fire
  // during/after createOffer but BEFORE the Firestore doc returns its ID.
  // ─────────────────────────────────────────────────────────────────────────
  final List<RTCIceCandidate> _pendingCallerCandidates = [];
  bool _callIdConfirmed = false;

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
      log(
        '📞 [CALLER] ========== STARTING OUTGOING CALL ==========',
        name: 'CallBloc.StartCall',
      );
      log(
        '📞 [CALLER] Target: ${event.receiverId} | Type: ${event.callType} | Caller: ${event.callerId}',
        name: 'CallBloc.StartCall',
      );

      _isCaller = true;

      // Reset buffer state for fresh call
      _pendingCallerCandidates.clear();
      _callIdConfirmed = false;

      log(
        '🧊 [CALLER] ICE buffer reset | callIdConfirmed=false',
        name: 'CallBloc.IceBuffer',
      );

      // Request permissions for video calls
      if (event.callType == CallType.video) {
        log(
          '📞 [CALLER] Requesting camera & mic permissions',
          name: 'CallBloc.StartCall',
        );
        final hasPermissions = await PermissionService.requestCameraAndMic();
        if (!hasPermissions) {
          log('❌ [CALLER] Permission denied', name: 'CallBloc.StartCall');
          emit(CallFailed('Camera or microphone permission denied'));
          return;
        }
        log('✅ [CALLER] Permissions granted', name: 'CallBloc.StartCall');
      }

      log(
        '📞 [CALLER] Initializing WebRTC (isVideo=${event.callType == CallType.video})',
        name: 'CallBloc.StartCall',
      );
      await _webrtc.initialize(isVideo: event.callType == CallType.video);

      // Wire callbacks BEFORE createOffer so ICE candidates go to the buffer
      _wireWebRtcCallbacks();

      log(
        '📞 [CALLER] Callbacks wired — ICE candidates will buffer until callId is confirmed',
        name: 'CallBloc.StartCall',
      );

      log('📞 [CALLER] Creating offer...', name: 'CallBloc.StartCall');
      final offer = await _webrtc.createOffer();
      final offerMap = {'type': offer.type, 'sdp': offer.sdp};

      log(
        '📞 [CALLER] Buffered caller ICE candidates so far: ${_pendingCallerCandidates.length}',
        name: 'CallBloc.IceBuffer',
      );

      log(
        '📞 [CALLER] Storing call in Firestore...',
        name: 'CallBloc.StartCall',
      );
      final firestoreCallId = await _repository.createCall(
        callerId: event.callerId,
        receiverId: event.receiverId,
        type: event.callType,
        offer: offerMap,
      );

      // ── CONFIRM callId and flush buffer ───────────────────────────────
      _currentCallId = firestoreCallId;
      _callIdConfirmed = true;

      log(
        '📞 [CALLER] ✅ callId confirmed: $_currentCallId | Flushing ${_pendingCallerCandidates.length} buffered ICE candidates',
        name: 'CallBloc.IceBuffer',
      );

      await _flushPendingCallerCandidates();

      log(
        '📞 [CALLER] ✅ ICE buffer flushed | callId=$_currentCallId',
        name: 'CallBloc.IceBuffer',
      );
      // ──────────────────────────────────────────────────────────────────

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

      log(
        '📞 [CALLER] Starting call document watcher',
        name: 'CallBloc.StartCall',
      );
      _listenToCallDocument(_currentCallId!);

      log(
        '📞 [CALLER] Starting ICE candidate watcher (receiving from receiver)',
        name: 'CallBloc.StartCall',
      );
      _listenToRemoteCandidates(_currentCallId!, isCaller: true);

      log(
        '📞 [CALLER] ========== CALL INITIATED - AWAITING ANSWER ==========',
        name: 'CallBloc.StartCall',
      );
    } catch (e) {
      log('❌ [CALLER] Error: $e', name: 'CallBloc.StartCall');
      emit(CallFailed('Failed to start call: $e'));
      await _cleanup();
    }
  }

  // ── Flush buffered caller ICE candidates to Firestore ──────────────────

  Future<void> _flushPendingCallerCandidates() async {
    if (_currentCallId == null || _pendingCallerCandidates.isEmpty) {
      log(
        '🧊 [CALLER] Nothing to flush | callId=$_currentCallId | buffered=${_pendingCallerCandidates.length}',
        name: 'CallBloc.IceBuffer',
      );
      return;
    }

    log(
      '🧊 [CALLER] Flushing ${_pendingCallerCandidates.length} buffered ICE candidates to Firestore | callId=$_currentCallId',
      name: 'CallBloc.IceBuffer',
    );

    final candidates = List<RTCIceCandidate>.from(_pendingCallerCandidates);
    _pendingCallerCandidates.clear();

    int successCount = 0;
    int failCount = 0;

    for (final candidate in candidates) {
      try {
        final candidateMap = {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        };
        await _repository.addCallerCandidate(_currentCallId!, candidateMap);
        successCount++;
        log(
          '🧊 [CALLER] ✅ Flushed buffered candidate [$successCount/${candidates.length}] | mid=${candidate.sdpMid} | candidate=${candidate.candidate?.substring(0, 40)}...',
          name: 'CallBloc.IceBuffer',
        );
      } catch (e) {
        failCount++;
        log(
          '🧊 [CALLER] ❌ Failed to flush buffered candidate: $e | mid=${candidate.sdpMid}',
          name: 'CallBloc.IceBuffer',
        );
      }
    }

    log(
      '🧊 [CALLER] Flush complete | success=$successCount | failed=$failCount | callId=$_currentCallId',
      name: 'CallBloc.IceBuffer',
    );
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
      log(
        '📱 [RECEIVER] ========== ACCEPTING INCOMING CALL ==========',
        name: 'CallBloc.AcceptCall',
      );
      log(
        '📱 [RECEIVER] From: ${event.call.callerId} | Type: ${event.call.type} | callId=${event.call.callId}',
        name: 'CallBloc.AcceptCall',
      );

      _isCaller = false;
      _currentCallId = event.call.callId;
      _callIdConfirmed = true; // receiver always has callId upfront
      _processedCandidateIds.clear();

      log(
        '📱 [RECEIVER] callId pre-confirmed: $_currentCallId (no buffering needed)',
        name: 'CallBloc.AcceptCall',
      );

      // Request permissions for video calls
      if (event.call.isVideo) {
        log(
          '📱 [RECEIVER] Requesting camera & mic permissions',
          name: 'CallBloc.AcceptCall',
        );
        final hasPermissions = await PermissionService.requestCameraAndMic();
        if (!hasPermissions) {
          log('❌ [RECEIVER] Permission denied', name: 'CallBloc.AcceptCall');
          emit(CallFailed('Camera or microphone permission denied'));
          await _repository.declineCall(event.call.callId);
          return;
        }
        log('✅ [RECEIVER] Permissions granted', name: 'CallBloc.AcceptCall');
      }

      log(
        '📱 [RECEIVER] Initializing WebRTC (isVideo=${event.call.isVideo})',
        name: 'CallBloc.AcceptCall',
      );
      await _webrtc.initialize(isVideo: event.call.isVideo);
      _wireWebRtcCallbacks();

      log(
        '📱 [RECEIVER] Starting ICE candidate watcher (receiving from caller)',
        name: 'CallBloc.AcceptCall',
      );
      _listenToRemoteCandidates(event.call.callId, isCaller: false);

      log(
        '📱 [RECEIVER] Setting remote description (offer from caller) | sdp_len=${event.call.offer?['sdp'].toString().length}',
        name: 'CallBloc.AcceptCall',
      );
      await _webrtc.setRemoteDescription(event.call.offer!);

      log('📱 [RECEIVER] Creating answer...', name: 'CallBloc.AcceptCall');
      final answer = await _webrtc.createAnswer();
      final answerMap = {'type': answer.type, 'sdp': answer.sdp};

      log(
        '📱 [RECEIVER] Storing answer in Firestore',
        name: 'CallBloc.AcceptCall',
      );
      await _repository.answerCall(
        callId: event.call.callId,
        answer: answerMap,
      );

      log(
        '📱 [RECEIVER] ✅ Answer sent | callId=${event.call.callId}',
        name: 'CallBloc.AcceptCall',
      );

      emit(
        CallConnecting(
          callId: event.call.callId,
          callType: event.call.type,
          localStream: _webrtc.localStream,
        ),
      );

      log(
        '📱 [RECEIVER] ========== HANDSHAKE COMPLETE - AWAITING ICE CANDIDATES ==========',
        name: 'CallBloc.AcceptCall',
      );
    } catch (e) {
      log('❌ [RECEIVER] Error: $e', name: 'CallBloc.AcceptCall');
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
      log(
        '❌ [END CALL] No callId available — bloc may have already cleaned up',
        name: 'CallBloc.EndCall',
      );
      emit(CallEnded('hungUp'));
      await _cleanup();
      return;
    }
    try {
      log(
        '📞 [END CALL] Ending call | callId=$callId',
        name: 'CallBloc.EndCall',
      );
      await _repository.endCall(callId, reason: 'hungUp');
    } catch (e) {
      log(
        '❌ [END CALL] Error updating Firestore: $e',
        name: 'CallBloc.EndCall',
      );
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
      log(
        '🤝 [CALLER] ========== ANSWER RECEIVED ==========',
        name: 'CallBloc.RemoteAnswer',
      );
      log(
        '🤝 [CALLER] Setting remote description | type=${event.answer['type']} | sdp_len=${(event.answer['sdp'] as String?)?.length}',
        name: 'CallBloc.RemoteAnswer',
      );
      await _webrtc.setRemoteDescription(event.answer);
      log(
        '🤝 [CALLER] ✅ Remote description set - HANDSHAKE COMPLETE',
        name: 'CallBloc.RemoteAnswer',
      );

      if (_currentCallId != null) {
        emit(
          CallConnecting(
            callId: _currentCallId!,
            callType: _callTypeFromState(),
            localStream: _webrtc.localStream,
          ),
        );
        log(
          '🤝 [CALLER] State -> CallConnecting | Awaiting ICE connectivity',
          name: 'CallBloc.RemoteAnswer',
        );
      }
    } catch (e) {
      log('❌ [CALLER] SDP error: $e', name: 'CallBloc.RemoteAnswer');
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
      final preview = event.candidate['candidate'].toString().substring(0, 40);
      log(
        '$role Adding remote ICE candidate | candidate=$preview... | mid=${event.candidate['sdpMid']}',
        name: 'CallBloc.IceCandidate',
      );
      await _webrtc.addRemoteCandidate(event.candidate);
      log(
        '$role ✅ Remote ICE candidate added successfully',
        name: 'CallBloc.IceCandidate',
      );
    } catch (e) {
      final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
      log(
        '$role ⚠️ Failed to add ICE candidate (non-fatal): $e',
        name: 'CallBloc.IceCandidate',
      );
    }
  }

  // ── LOCAL ICE CANDIDATE ────────────────────────────────────────────────

  Future<void> _onLocalIceCandidate(
    LocalIceCandidateEvent event,
    Emitter<CallState> emit,
  ) async {
    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    final preview = event.candidate.candidate?.substring(0, 40) ?? 'null';

    if (_isCaller) {
      // ── RACE CONDITION GUARD ─────────────────────────────────────────
      // If callId is not yet confirmed (Firestore hasn't returned the doc ID),
      // buffer the candidate instead of trying to write with a wrong/null ID.
      if (!_callIdConfirmed || _currentCallId == null) {
        _pendingCallerCandidates.add(event.candidate);
        log(
          '🧊 [CALLER] ICE candidate BUFFERED (callId not yet confirmed) | buffered=${_pendingCallerCandidates.length} | candidate=$preview... | mid=${event.candidate.sdpMid}',
          name: 'CallBloc.IceBuffer',
        );
        return;
      }
      // ────────────────────────────────────────────────────────────────

      log(
        '$role Uploading local ICE candidate to Firestore | callId=$_currentCallId | candidate=$preview... | mid=${event.candidate.sdpMid}',
        name: 'CallBloc.IceCandidate',
      );

      final candidateMap = {
        'candidate': event.candidate.candidate,
        'sdpMid': event.candidate.sdpMid,
        'sdpMLineIndex': event.candidate.sdpMLineIndex,
      };

      try {
        await _repository.addCallerCandidate(_currentCallId!, candidateMap);
        log(
          '📞 [CALLER] ✅ Caller ICE candidate uploaded to Firestore | callId=$_currentCallId | mid=${event.candidate.sdpMid}',
          name: 'CallBloc.IceCandidate',
        );
      } catch (e) {
        log(
          '📞 [CALLER] ❌ Failed to upload caller ICE candidate: $e | callId=$_currentCallId',
          name: 'CallBloc.IceCandidate',
        );
      }
    } else {
      // Receiver always has callId confirmed before ICE fires
      if (_currentCallId == null) {
        log(
          '📱 [RECEIVER] ⚠️ Skipping ICE candidate upload — callId is null',
          name: 'CallBloc.IceCandidate',
        );
        return;
      }

      log(
        '$role Uploading local ICE candidate to Firestore | callId=$_currentCallId | candidate=$preview... | mid=${event.candidate.sdpMid}',
        name: 'CallBloc.IceCandidate',
      );

      final candidateMap = {
        'candidate': event.candidate.candidate,
        'sdpMid': event.candidate.sdpMid,
        'sdpMLineIndex': event.candidate.sdpMLineIndex,
      };

      try {
        await _repository.addReceiverCandidate(_currentCallId!, candidateMap);
        log(
          '📱 [RECEIVER] ✅ Receiver ICE candidate uploaded to Firestore | callId=$_currentCallId | mid=${event.candidate.sdpMid}',
          name: 'CallBloc.IceCandidate',
        );
      } catch (e) {
        log(
          '📱 [RECEIVER] ❌ Failed to upload receiver ICE candidate: $e | callId=$_currentCallId',
          name: 'CallBloc.IceCandidate',
        );
      }
    }
  }

  // ── CONNECTION STATE CHANGED ───────────────────────────────────────────

  Future<void> _onConnectionStateChanged(
    ConnectionStateChangedEvent event,
    Emitter<CallState> emit,
  ) async {
    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    log(
      '$role 🔄 Connection state changed: ${event.state}',
      name: 'CallBloc.Connection',
    );

    switch (event.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        log(
          '$role 🎉 ========== PEER CONNECTION ESTABLISHED ==========',
          name: 'CallBloc.Connection',
        );
        _timeoutTimer?.cancel();
        if (_currentCallId != null) {
          log(
            '$role Marking call as connected in Firestore | callId=$_currentCallId',
            name: 'CallBloc.Connection',
          );
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
        log('$role ✅ State -> CallActive', name: 'CallBloc.Connection');

      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        log(
          '$role ⚠️ Peer connection disconnected',
          name: 'CallBloc.Connection',
        );
        if (state is CallActive && _currentCallId != null) {
          log('$role State -> CallReconnecting', name: 'CallBloc.Connection');
          emit(CallReconnecting(_currentCallId!));
        }

      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        log(
          '$role ❌ ========== PEER CONNECTION FAILED ==========',
          name: 'CallBloc.Connection',
        );
        if (_currentCallId != null) {
          await _repository.endCall(_currentCallId!, reason: 'failed');
        }
        emit(CallFailed('iceFailure'));
        await _cleanup();

      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        log(
          '$role Connection closed — cleanup already handled',
          name: 'CallBloc.Connection',
        );
        break;

      default:
        log(
          '$role Unhandled connection state: ${event.state}',
          name: 'CallBloc.Connection',
        );
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

  // ── REMOTE STREAM RECEIVED ─────────────────────────────────────────────

  void _onRemoteStreamReceived(
    RemoteStreamReceivedEvent event,
    Emitter<CallState> emit,
  ) {
    final role = _isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    log(
      '$role 📡 ========== REMOTE STREAM RECEIVED ==========',
      name: 'CallBloc.RemoteStream',
    );
    log(
      '$role Remote stream tracks: video=${event.stream.getVideoTracks().length}, audio=${event.stream.getAudioTracks().length}',
      name: 'CallBloc.RemoteStream',
    );

    final currentState = state;
    if (currentState is CallActive) {
      log(
        '$role Updating CallActive state with remote stream',
        name: 'CallBloc.RemoteStream',
      );
      emit((currentState).copyWith(remoteStream: event.stream));
    } else if (currentState is CallConnecting) {
      log(
        '$role Remote stream arrived during CallConnecting — will be applied on transition to CallActive',
        name: 'CallBloc.RemoteStream',
      );
    }
  }

  // ── CALL REMOTELY DECLINED ─────────────────────────────────────────────

  Future<void> _onCallRemotelyDeclined(
    CallRemotelyDeclinedEvent event,
    Emitter<CallState> emit,
  ) async {
    log('📡 Remote side declined the call', name: 'CallBloc.Remote');
    emit(CallEnded('declined'));
    await _cleanup();
  }

  // ── CALL REMOTELY ENDED ────────────────────────────────────────────────

  Future<void> _onCallRemotelyEnded(
    CallRemotelyEndedEvent event,
    Emitter<CallState> emit,
  ) async {
    log(
      '📡 Remote side ended the call | reason=${event.reason}',
      name: 'CallBloc.Remote',
    );
    emit(CallEnded(event.reason));
    await _cleanup();
  }

  // ── Firestore listeners ────────────────────────────────────────────────

  void _listenToCallDocument(String callId) {
    log(
      '📡 [CALLER] Subscribing to call document | callId=$callId',
      name: 'CallBloc.Firestore',
    );
    _callWatcher?.cancel();
    _callWatcher = _repository.watchCall(callId).listen((snap) {
      if (!snap.exists || isClosed) return;
      final data = snap.data() as Map<String, dynamic>;
      final status = CallStatusX.fromString(data['status'] as String? ?? '');

      log(
        '📡 [CALLER] Call document update | status=$status | callId=$callId',
        name: 'CallBloc.Firestore',
      );

      switch (status) {
        case CallStatus.connecting:
          final answer = data['answer'] as Map<String, dynamic>?;
          if (answer != null && _isCaller) {
            log(
              '📡 [CALLER] ✅ Answer received from receiver',
              name: 'CallBloc.Firestore',
            );
            add(RemoteAnswerReceivedEvent(answer));
          }

        case CallStatus.declined:
          log(
            '📡 [CALLER] ❌ Call declined by receiver',
            name: 'CallBloc.Firestore',
          );
          if (!isClosed) add(CallRemotelyDeclinedEvent());

        case CallStatus.ended:
          log(
            '📡 [CALLER] Call ended by remote | reason=${data['endReason']}',
            name: 'CallBloc.Firestore',
          );
          if (!isClosed && state is! CallEnded) {
            add(
              CallRemotelyEndedEvent(data['endReason'] as String? ?? 'hungUp'),
            );
          }

        default:
          break;
      }
    });
  }

  void _listenToRemoteCandidates(String callId, {required bool isCaller}) {
    final role = isCaller ? '📞 [CALLER]' : '📱 [RECEIVER]';
    final listeningSide = isCaller ? 'receiver' : 'caller';
    log(
      '$role Subscribing to ICE candidates from $listeningSide | callId=$callId',
      name: 'CallBloc.Firestore',
    );

    _remoteIceWatcher?.cancel();

    final stream = isCaller
        ? _repository.watchReceiverCandidates(callId)
        : _repository.watchCallerCandidates(callId);

    _remoteIceWatcher = stream.listen((snap) {
      if (isClosed) return;

      int newCount = 0;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final id = change.doc.id;
          if (_processedCandidateIds.contains(id)) continue;
          _processedCandidateIds.add(id);
          newCount++;

          final data = change.doc.data() as Map<String, dynamic>;
          final preview = data['candidate'].toString().substring(0, 40);
          log(
            '$role 📡 New remote ICE candidate [docId=$id] | candidate=$preview... | mid=${data['sdpMid']}',
            name: 'CallBloc.Firestore',
          );
          add(RemoteIceCandidateEvent(data));
        }
      }

      if (newCount > 0) {
        log(
          '$role Dispatched $newCount new remote ICE candidate(s) | total processed=${_processedCandidateIds.length}',
          name: 'CallBloc.Firestore',
        );
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
    log(
      '🧹 [CLEANUP] Cancelling timers and subscriptions | callId=$_currentCallId | buffered=${_pendingCallerCandidates.length}',
      name: 'CallBloc.Cleanup',
    );
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _callWatcher?.cancel();
    _remoteIceWatcher?.cancel();
    _processedCandidateIds.clear();
    _pendingCallerCandidates.clear();
    _callIdConfirmed = false;
    _currentCallId = null;
    await _webrtc.dispose();
    log('🧹 [CLEANUP] Done', name: 'CallBloc.Cleanup');
  }

  @override
  Future<void> close() async {
    log('🛑 ========== CALL BLOC CLOSED ==========', name: 'CallBloc.Cleanup');
    await _cleanup();
    return super.close();
  }
}
