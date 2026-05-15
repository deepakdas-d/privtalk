import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as developer;

import '../datasource/ice_datasource.dart';

final _logger = developer.log;

/// Owns the RTCPeerConnection and local/remote media.
/// Callers listen to [onIceCandidate], [onConnectionStateChange],
/// [onRemoteStream], and [onRenegotiationNeeded].
class WebRtcService {
  final IceDatasource _iceDatasource;

  WebRtcService({IceDatasource? iceDatasource})
    : _iceDatasource = iceDatasource ?? IceDatasource();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Callbacks wired up by CallBloc
  void Function(RTCIceCandidate)? onIceCandidate;
  void Function(RTCPeerConnectionState)? onConnectionStateChange;
  void Function(MediaStream)? onRemoteStream;
  void Function()? onRenegotiationNeeded;

  RTCPeerConnection? get pc => _pc;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> initialize({required bool isVideo}) async {
    _logger(
      '🎬 [WebRTC] Initializing peer connection | isVideo=$isVideo | platform=${kIsWeb ? "WEB" : "MOBILE"}',
    );

    final iceServers = await _iceDatasource.fetchIceServers();
    _logger('🔗 [WebRTC] ICE Servers fetched: ${iceServers.length} servers');

    final config = {
      'iceServers': iceServers,
      'iceCandidatePoolSize': 10,
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);
    _logger('✅ [WebRTC] PeerConnection created');

    _localStream = await _getLocalStream(isVideo: isVideo);
    _logger(
      '📹 [WebRTC] Local stream acquired | videoTracks=${_localStream?.getVideoTracks().length} | audioTracks=${_localStream?.getAudioTracks().length}',
    );

    // Add tracks (unified-plan)
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
      _logger('📤 [WebRTC] Added ${track.kind} track to peer connection');
    }

    _wireCallbacks();
    _logger('✅ [WebRTC] Initialization complete');
  }

  Future<MediaStream> _getLocalStream({required bool isVideo}) async {
    _logger(
      '📥 [WebRTC] Requesting media devices | isVideo=$isVideo | platform=${kIsWeb ? "WEB" : "MOBILE"}',
    );

    final Map<String, dynamic> constraints = {'audio': true};

    if (isVideo) {
      if (kIsWeb) {
        constraints['video'] = {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'facingMode': 'user',
        };
      } else {
        constraints['video'] = {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
        };
      }
    } else {
      constraints['video'] = false;
    }

    try {
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _logger('✅ [WebRTC] Media stream acquired | constraints=$constraints');
      return stream;
    } catch (e) {
      _logger(
        '⚠️ [WebRTC] getUserMedia failed, retrying with minimal constraints: $e',
      );
      // Retry with minimal constraints if initial attempt fails
      final fallbackConstraints = {
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      };
      final stream = await navigator.mediaDevices.getUserMedia(
        fallbackConstraints,
      );
      _logger('✅ [WebRTC] Media stream acquired via fallback');
      return stream;
    }
  }

  void _wireCallbacks() {
    _logger('🔌 [WebRTC] Wiring peer connection callbacks');

    _pc!.onIceCandidate = (candidate) {
      _logger(
        '🧊 [WebRTC] onIceCandidate fired! candidate=${candidate.candidate}',
      );
      if (candidate.candidate != null) {
        _logger('🧊 [WebRTC] ICE Candidate generated...');
        onIceCandidate?.call(candidate);
      } else {
        _logger('⚠️ [WebRTC] ICE gathering complete (null candidate)');
      }
    };
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _logger(
          '🧊 [WebRTC] ICE Candidate generated | candidate=${candidate.candidate?.substring(0, 50)}... | mid=${candidate.sdpMid}',
        );
        onIceCandidate?.call(candidate);
      }
    };

    _pc!.onConnectionState = (state) {
      _logger('🔄 [WebRTC] Connection state changed | state=$state');
      onConnectionStateChange?.call(state);
    };

    _pc!.onTrack = (event) {
      _logger(
        '📡 [WebRTC] Remote track received | kind=${event.track.kind} | streams=${event.streams.length}',
      );
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _logger(
          '✅ [WebRTC] Remote stream set | videoTracks=${_remoteStream?.getVideoTracks().length} | audioTracks=${_remoteStream?.getAudioTracks().length}',
        );
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _pc!.onRenegotiationNeeded = () {
      _logger('🔄 [WebRTC] Renegotiation needed');
      onRenegotiationNeeded?.call();
    };

    _logger('✅ [WebRTC] Callbacks wired');
  }

  // ── Offer / Answer ────────────────────────────────────────────────────────

  Future<RTCSessionDescription> createOffer() async {
    _logger('📋 [WebRTC] Creating offer with offerToReceiveAudio=1');
    final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
    _logger(
      '✅ [WebRTC] Offer created | type=${offer.type} | sdp_length=${offer.sdp?.length}',
    );
    await _pc!.setLocalDescription(offer);
    _logger('✅ [WebRTC] Local description set (offer)');
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    _logger(
      '📋 [WebRTC] Creating answer with offerToReceiveAudio=1, offerToReceiveVideo=1',
    );
    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    _logger(
      '✅ [WebRTC] Answer created | type=${answer.type} | sdp_length=${answer.sdp?.length}',
    );
    await _pc!.setLocalDescription(answer);
    _logger('✅ [WebRTC] Local description set (answer)');
    return answer;
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    _logger(
      '📋 [WebRTC] Setting remote description | type=${sdpMap['type']} | sdp_length=${(sdpMap['sdp'] as String?)?.length}',
    );
    final desc = RTCSessionDescription(
      sdpMap['sdp'] as String,
      sdpMap['type'] as String,
    );
    await _pc!.setRemoteDescription(desc);
    _logger('✅ [WebRTC] Remote description set');
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidateMap) async {
    _logger(
      '🧊 [WebRTC] Adding remote ICE candidate | candidate=${candidateMap['candidate']?.toString().substring(0, 50)}... | mid=${candidateMap['sdpMid']}',
    );
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );
    await _pc!.addCandidate(candidate);
    _logger('✅ [WebRTC] Remote ICE candidate added');
  }

  // ── Camera / Mic toggles ─────────────────────────────────────────────────

  void toggleMic({required bool enabled}) {
    _logger('🔊 [WebRTC] Toggle mic | enabled=$enabled');
    _localStream?.getAudioTracks().forEach((t) => t.enabled = enabled);
  }

  void toggleCamera({required bool enabled}) {
    _logger('📹 [WebRTC] Toggle camera | enabled=$enabled');
    _localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
  }

  Future<void> switchCamera() async {
    _logger('🔄 [WebRTC] Switching camera');
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
      _logger('✅ [WebRTC] Camera switched');
    } else {
      _logger('⚠️ [WebRTC] No video tracks to switch');
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _logger('🛑 [WebRTC] Disposing WebRTC service');
    _localStream?.getTracks().forEach((t) => t.stop());
    _logger('  - Local tracks stopped: ${_localStream?.getTracks().length}');
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    _logger('✅ [WebRTC] Disposed');
  }
}
