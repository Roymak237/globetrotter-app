import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:globetrotter/utils/constants.dart";
import "package:http/http.dart" as http;
import "package:web_socket_channel/web_socket_channel.dart";

/// How a call is progressing, from the local device's point of view.
enum CallStage { idle, dialling, ringing, connecting, active, ended }

/// The other side of a call, and what the local device is doing about it.
class CallSession {
  final String callId;
  final String roomId;
  final String peer;
  final String peerDisplayName;
  final String peerAvatarUrl;
  final bool video;
  final bool incoming;

  const CallSession({
    required this.callId,
    required this.roomId,
    required this.peer,
    required this.peerDisplayName,
    required this.peerAvatarUrl,
    required this.video,
    required this.incoming,
  });

  String get title => peerDisplayName.isNotEmpty ? peerDisplayName : peer;
}

/// Peer-to-peer audio and video calling.
///
/// Signalling runs over a websocket to the backend; the audio and video
/// themselves travel directly between devices via WebRTC, so the server never
/// sees or stores call content.
///
/// One-to-one only. Group rooms ring every member, but the first to accept
/// takes the call — mesh calling for a large group would need far more
/// bandwidth than a phone on mobile data can give.
class CallService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  String? _token;
  String? _username;

  CallStage _stage = CallStage.idle;
  CallSession? _session;
  String? _error;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _renderersReady = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;

  List<Map<String, dynamic>> _iceServers = const [
    {"urls": "stun:stun.l.google.com:19302"},
  ];

  /// ICE candidates that arrive before the remote description is set must be
  /// held back, because adding one early throws and loses the candidate.
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  CallStage get stage => _stage;
  CallSession? get session => _session;
  String? get error => _error;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;
  bool get speakerOn => _speakerOn;
  bool get isConnected => _channel != null;

  bool get inCall => _stage != CallStage.idle && _stage != CallStage.ended;

  /// Raised when someone rings this device, so the UI can show the incoming
  /// call screen from wherever the traveller happens to be.
  void Function(CallSession session)? onIncomingCall;

  // ---------------------------------------------------------------------
  // Signalling connection
  // ---------------------------------------------------------------------

  /// Open the signalling socket. Safe to call repeatedly.
  Future<void> connect(String token, String username) async {
    if (_channel != null && _token == token) return;
    _token = token;
    _username = username;

    await _ensureRenderers();
    await _loadIceServers(token);

    final base = Uri.parse(AppConstants.backendBaseUrl);
    final uri = base.replace(
      scheme: base.scheme == "https" ? "wss" : "ws",
      path: "${AppConstants.apiPrefix}/chat/ws",
      // Browsers cannot set headers on a websocket handshake, so the token
      // travels as a query parameter. The connection is TLS in production,
      // which keeps it off the wire in clear text.
      queryParameters: {"token": token},
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onFrame,
        onDone: _onSocketClosed,
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
      // Idle websockets are dropped by proxies; a periodic ping keeps the
      // connection alive so an incoming call can still reach this device.
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(
        const Duration(seconds: 40),
        (_) => _send({"type": "ping"}),
      );
    } catch (_) {
      _channel = null;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    notifyListeners();
  }

  void _onSocketClosed() {
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (inCall) _fail("The connection dropped.");
    notifyListeners();
  }

  Future<void> _loadIceServers(String token) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConstants.backendBaseUrl}"
            "${AppConstants.apiPrefix}/chat/calls/ice"),
        headers: {"Authorization": "Bearer $token"},
      ).timeout(AppConstants.apiTimeout);
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final servers = body["ice_servers"] as List<dynamic>? ?? const [];
      if (servers.isNotEmpty) {
        _iceServers = servers.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // Keep the built-in STUN server, which covers most networks.
    }
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  // ---------------------------------------------------------------------
  // Inbound frames
  // ---------------------------------------------------------------------

  Future<void> _onFrame(dynamic raw) async {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (message["type"]) {
      case "ring":
        await _onRing(message);
        break;
      case "ringing":
        _session = _session == null
            ? null
            : CallSession(
                callId: message["call_id"]?.toString() ?? "",
                roomId: _session!.roomId,
                peer: _session!.peer,
                peerDisplayName: _session!.peerDisplayName,
                peerAvatarUrl: _session!.peerAvatarUrl,
                video: _session!.video,
                incoming: false,
              );
        _stage = CallStage.ringing;
        notifyListeners();
        break;
      case "accepted":
        await _onAccepted(message);
        break;
      case "offer":
        await _onOffer(message);
        break;
      case "answer":
        await _onAnswer(message);
        break;
      case "ice":
        await _onRemoteCandidate(message);
        break;
      case "hangup":
        await _teardown(
          message["reason"] == "decline" ? "Call declined." : null,
        );
        break;
      case "error":
        _fail(message["error"]?.toString() ?? "Call failed.");
        break;
    }
  }

  Future<void> _onRing(Map<String, dynamic> message) async {
    // Already busy: decline rather than leaving the caller ringing forever.
    if (inCall) {
      _send({"type": "decline", "call_id": message["call_id"]});
      return;
    }

    _session = CallSession(
      callId: message["call_id"]?.toString() ?? "",
      roomId: message["room_id"]?.toString() ?? "",
      peer: message["from"]?.toString() ?? "",
      peerDisplayName: message["from_display_name"]?.toString() ?? "",
      peerAvatarUrl: message["from_avatar_url"]?.toString() ?? "",
      video: message["video"] == true,
      incoming: true,
    );
    _stage = CallStage.ringing;
    _error = null;
    notifyListeners();
    onIncomingCall?.call(_session!);
  }

  Future<void> _onAccepted(Map<String, dynamic> message) async {
    final session = _session;
    if (session == null || session.incoming) return;

    // The caller creates the offer once someone picks up, so the callee's
    // media is already flowing by the time negotiation starts.
    _stage = CallStage.connecting;
    notifyListeners();

    final peer = message["by"]?.toString() ?? session.peer;
    _session = CallSession(
      callId: session.callId,
      roomId: session.roomId,
      peer: peer,
      peerDisplayName: session.peerDisplayName,
      peerAvatarUrl: session.peerAvatarUrl,
      video: session.video,
      incoming: false,
    );

    await _preparePeerConnection(video: session.video);
    final connection = _peerConnection;
    if (connection == null) return;

    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    _send({
      "type": "offer",
      "call_id": session.callId,
      "to": peer,
      "sdp": offer.sdp,
      "sdp_type": offer.type,
    });
  }

  Future<void> _onOffer(Map<String, dynamic> message) async {
    final session = _session;
    if (session == null) return;

    await _preparePeerConnection(video: session.video);
    final connection = _peerConnection;
    if (connection == null) return;

    await connection.setRemoteDescription(RTCSessionDescription(
      message["sdp"]?.toString(),
      message["sdp_type"]?.toString() ?? "offer",
    ));
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await connection.createAnswer();
    await connection.setLocalDescription(answer);
    _send({
      "type": "answer",
      "call_id": session.callId,
      "to": message["from"]?.toString() ?? session.peer,
      "sdp": answer.sdp,
      "sdp_type": answer.type,
    });

    _stage = CallStage.active;
    notifyListeners();
  }

  Future<void> _onAnswer(Map<String, dynamic> message) async {
    final connection = _peerConnection;
    if (connection == null) return;

    await connection.setRemoteDescription(RTCSessionDescription(
      message["sdp"]?.toString(),
      message["sdp_type"]?.toString() ?? "answer",
    ));
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    _stage = CallStage.active;
    notifyListeners();
  }

  Future<void> _onRemoteCandidate(Map<String, dynamic> message) async {
    final candidate = RTCIceCandidate(
      message["candidate"]?.toString(),
      message["sdp_mid"]?.toString(),
      (message["sdp_m_line_index"] as num?)?.toInt(),
    );

    if (!_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peerConnection?.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    for (final candidate in _pendingCandidates) {
      await _peerConnection?.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  // ---------------------------------------------------------------------
  // Media and peer connection
  // ---------------------------------------------------------------------

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> _preparePeerConnection({required bool video}) async {
    if (_peerConnection != null) return;

    await _ensureRenderers();

    final stream = await navigator.mediaDevices.getUserMedia({
      "audio": true,
      "video": video
          ? {
              "facingMode": "user",
              "width": {"ideal": 640},
              "height": {"ideal": 480},
            }
          : false,
    });
    _localStream = stream;
    localRenderer.srcObject = stream;

    final connection = await createPeerConnection({
      "iceServers": _iceServers,
      "sdpSemantics": "unified-plan",
    });

    for (final track in stream.getTracks()) {
      await connection.addTrack(track, stream);
    }

    connection.onIceCandidate = (candidate) {
      final session = _session;
      if (session == null || candidate.candidate == null) return;
      _send({
        "type": "ice",
        "call_id": session.callId,
        "to": session.peer,
        "candidate": candidate.candidate,
        "sdp_mid": candidate.sdpMid,
        "sdp_m_line_index": candidate.sdpMLineIndex,
      });
    };

    connection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        notifyListeners();
      }
    };

    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _stage = CallStage.active;
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _teardown("The call could not connect.");
      }
    };

    _peerConnection = connection;
    _cameraOff = !video;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Ring the other members of [roomId].
  Future<void> startCall({
    required String roomId,
    required String peer,
    required String peerDisplayName,
    bool video = false,
  }) async {
    if (inCall) return;
    if (_channel == null && _token != null && _username != null) {
      await connect(_token!, _username!);
    }
    if (_channel == null) {
      _fail("You are offline. Try again when you have a connection.");
      return;
    }

    _error = null;
    _session = CallSession(
      callId: "",
      roomId: roomId,
      peer: peer,
      peerDisplayName: peerDisplayName,
      peerAvatarUrl: "",
      video: video,
      incoming: false,
    );
    _stage = CallStage.dialling;
    notifyListeners();

    _send({"type": "call", "room_id": roomId, "video": video});
  }

  /// Answer the call that is currently ringing.
  Future<void> accept() async {
    final session = _session;
    if (session == null || !session.incoming) return;

    _stage = CallStage.connecting;
    notifyListeners();

    // Media is opened before accepting so that, if permission is refused, the
    // caller is declined cleanly instead of connecting to silence.
    try {
      await _preparePeerConnection(video: session.video);
    } catch (_) {
      _send({"type": "decline", "call_id": session.callId});
      _fail("Microphone or camera permission was refused.");
      return;
    }

    _send({"type": "accept", "call_id": session.callId});
  }

  /// Refuse an incoming call.
  Future<void> decline() async {
    final session = _session;
    if (session != null) {
      _send({"type": "decline", "call_id": session.callId});
    }
    await _teardown(null);
  }

  /// End a call that is under way, or give up on one that is ringing.
  Future<void> hangUp() async {
    final session = _session;
    if (session != null && session.callId.isNotEmpty) {
      _send({"type": "hangup", "call_id": session.callId});
    }
    await _teardown(null);
  }

  void toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return;
    _muted = !_muted;
    for (final track in tracks) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    _cameraOff = !_cameraOff;
    for (final track in tracks) {
      track.enabled = !_cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isNotEmpty) {
      await Helper.setSpeakerphoneOn(_speakerOn);
    }
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    unawaited(_teardown(message));
  }

  Future<void> _teardown(String? message) async {
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();

    for (final track
        in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }

    _muted = false;
    _cameraOff = false;
    _error = message;
    _stage = _session == null ? CallStage.idle : CallStage.ended;
    _session = null;
    notifyListeners();

    // Settle back to idle so a stale "ended" screen does not linger.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_stage == CallStage.ended) {
        _stage = CallStage.idle;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _peerConnection?.close();
    _localStream?.dispose();
    if (_renderersReady) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}
