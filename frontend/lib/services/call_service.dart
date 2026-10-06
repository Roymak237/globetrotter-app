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
  /// How long a caller waits before giving up on an unanswered call.
  ///
  /// Without this a call that nobody picks up rings until the caller closes
  /// the screen, which is indistinguishable from the app being broken.
  static const Duration ringTimeout = Duration(seconds: 45);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _ringTimer;
  Timer? _settleTimer;
  bool _disposed = false;

  /// How a signalling socket gets opened.
  ///
  /// Injectable so the call lifecycle can be driven in a test without a
  /// server or a browser. The call bugs worth catching live in this state
  /// machine, not in the socket, and they are unreachable if opening one is
  /// hard-wired.
  @visibleForTesting
  WebSocketChannel Function(Uri uri) channelFactory = WebSocketChannel.connect;

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

  /// Whether the server offered a TURN relay.
  ///
  /// STUN alone cannot get media through symmetric NAT, which is what most
  /// mobile carriers use. When this is false a call can negotiate perfectly
  /// and still end with neither side hearing anything, so the UI says so
  /// rather than leaving the pair to guess.
  bool _hasTurn = false;
  bool get hasTurn => _hasTurn;

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

    // Best-effort, deliberately. The socket is what lets an incoming call
    // reach this device at all; the video surfaces are only needed once a
    // call is actually answered, and _preparePeerConnection initialises them
    // again before use. Letting a renderer failure abort here would take out
    // signalling — and with it every incoming call — over a problem that
    // only affects video.
    try {
      await _ensureRenderers();
    } catch (_) {
      // Surfaced later by _preparePeerConnection, which needs them for real.
    }
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
      final channel = channelFactory(uri);
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
    _notify();
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _notify();
  }

  void _onSocketClosed() {
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (inCall) _fail("The connection dropped.");
    _notify();
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
      _hasTurn = body["has_turn"] == true;
    } catch (_) {
      // Fall back to the built-in STUN server. That is enough on broadband
      // and on any NAT that reuses one public mapping per client, but not on
      // the carrier-grade NAT most mobile networks run, where each
      // destination gets its own mapping and the address STUN reported is
      // already stale. `_hasTurn` stays false, which is what makes the
      // failure message later on say so rather than blame the app.
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
        _onRinging(message);
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

  /// The server accepted the request and rang whoever it could find.
  ///
  /// `reached` is how many devices the ring actually landed on. Zero means
  /// nobody was connected to take it. This used to be ignored, so the caller
  /// was shown "ringing" for a call that had already failed and would never
  /// ring anywhere — no error, no timeout, nothing. That is precisely what
  /// "calls are not going through" looks like from the caller's side, and it
  /// is indistinguishable from the network being broken.
  void _onRinging(Map<String, dynamic> message) {
    final session = _session;
    if (session == null) return;

    final reached = (message["reached"] as num?)?.toInt() ?? 0;
    if (reached <= 0) {
      _fail("No one is online to take this call right now.");
      return;
    }

    _session = CallSession(
      callId: message["call_id"]?.toString() ?? "",
      roomId: session.roomId,
      peer: session.peer,
      peerDisplayName: session.peerDisplayName,
      peerAvatarUrl: session.peerAvatarUrl,
      video: session.video,
      incoming: false,
    );
    _stage = CallStage.ringing;
    _notify();

    // A ring that is never answered has to end by itself. Leaving it running
    // holds the microphone and looks identical to a hung call.
    _ringTimer?.cancel();
    _ringTimer = Timer(ringTimeout, () {
      if (_stage != CallStage.ringing) return;
      final current = _session;
      if (current != null && current.callId.isNotEmpty) {
        _send({"type": "hangup", "call_id": current.callId});
      }
      _fail("No answer.");
    });
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
    _notify();
    onIncomingCall?.call(_session!);
  }

  Future<void> _onAccepted(Map<String, dynamic> message) async {
    final session = _session;
    if (session == null || session.incoming) return;

    // Someone picked up, so the unanswered-call timer no longer applies.
    _ringTimer?.cancel();
    _ringTimer = null;

    // The caller creates the offer once someone picks up, so the callee's
    // media is already flowing by the time negotiation starts.
    _stage = CallStage.connecting;
    _notify();

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
    _notify();
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
    _notify();
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
        _notify();
      }
    };

    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _stage = CallStage.active;
        _notify();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        // Without a TURN relay this is the expected outcome on any network
        // that uses symmetric NAT, which most mobile carriers do. Signalling
        // succeeds, negotiation completes, and the media has nowhere to go.
        // Saying so gives the caller something to act on instead of a dead
        // end that looks like a bug in the app.
        _teardown(_hasTurn
            ? "The call could not connect."
            : "The call could not connect. This often happens on mobile "
                "data — try again on Wi-Fi.");
      }
    };

    _peerConnection = connection;
    _cameraOff = !video;
    _notify();
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
    _notify();

    _send({"type": "call", "room_id": roomId, "video": video});
  }

  /// Answer the call that is currently ringing.
  Future<void> accept() async {
    final session = _session;
    if (session == null || !session.incoming) return;

    _stage = CallStage.connecting;
    _notify();

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
    _notify();
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    _cameraOff = !_cameraOff;
    for (final track in tracks) {
      track.enabled = !_cameraOff;
    }
    _notify();
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
    _notify();
  }

  void _fail(String message) {
    _error = message;
    unawaited(_teardown(message));
  }

  Future<void> _teardown(String? message) async {
    _ringTimer?.cancel();
    _ringTimer = null;
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
    _notify();

    // Settle back to idle so a stale "ended" screen does not linger.
    //
    // A cancellable timer rather than Future.delayed: hanging up and
    // immediately leaving the screen disposes this service while the delay is
    // still pending, and an uncancellable callback then notifies a disposed
    // listener. That is a real crash on a perfectly ordinary sequence — end
    // call, go back — and it was caught by the tests in call_service_test.
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 600), () {
      if (_stage == CallStage.ended) {
        _stage = CallStage.idle;
        _notify();
      }
    });
  }

  /// notifyListeners, unless this service has been disposed.
  ///
  /// Call teardown is asynchronous — stopping tracks and closing a peer
  /// connection both await — so disposal can land part-way through it.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _ringTimer?.cancel();
    _settleTimer?.cancel();
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
