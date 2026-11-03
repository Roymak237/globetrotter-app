import "dart:async";
import "dart:convert";
import "dart:math" as math;

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

/// Thrown when a call ends while its media is still being set up.
class _CallCancelled implements Exception {
  const _CallCancelled();
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

  /// How long media may take to flow once both sides have agreed to talk.
  static const Duration connectTimeout = Duration(seconds: 30);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _ringTimer;
  Timer? _settleTimer;
  Timer? _connectTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// Bumped whenever the socket is replaced, so callbacks from an old socket
  /// cannot tear down a newer one.
  int _generation = 0;
  Future<void>? _connecting;
  int _reconnectAttempts = 0;

  /// Bumped on every teardown, so async work for an ended call stops instead
  /// of leaking a microphone or touching the next call.
  int _callGeneration = 0;
  Future<void>? _preparing;

  /// How a signalling socket gets opened.
  ///
  /// Injectable so the call lifecycle can be driven in a test without a
  /// server or a browser. The call bugs worth catching live in this state
  /// machine, not in the socket, and they are unreachable if opening one is
  /// hard-wired.
  @visibleForTesting
  WebSocketChannel Function(Uri uri) channelFactory = WebSocketChannel.connect;

  /// How the ICE server list is fetched; injectable for the same reason.
  @visibleForTesting
  Future<http.Response> Function(Uri url, {Map<String, String>? headers})
      httpGet = http.get;

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
  ///
  /// Concurrent calls for the same session share one attempt; a different
  /// session replaces the old socket instead of leaking it.
  Future<void> connect(String token, String username) {
    if (_token == token) {
      _username = username;
      if (_channel != null) return Future<void>.value();
      final pending = _connecting;
      if (pending != null) return pending;
    } else {
      _reconnectAttempts = 0;
      if (inCall) unawaited(hangUp());
    }
    _cancelReconnect();
    _closeChannel();
    _token = token;
    _username = username;

    final generation = _generation;
    late final Future<void> attempt;
    attempt = _open(token, generation).whenComplete(() {
      if (identical(_connecting, attempt)) _connecting = null;
    });
    _connecting = attempt;
    return attempt;
  }

  /// Reconnect now if signed in but offline, e.g. when the app resumes.
  void ensureConnected() {
    final token = _token;
    final username = _username;
    if (_disposed || token == null || username == null) return;
    if (_channel != null || _connecting != null) return;
    _cancelReconnect();
    unawaited(connect(token, username));
  }

  Future<void> _open(String token, int generation) async {
    // Video renderers are deliberately not initialised here. The socket is
    // what lets an incoming call reach this device at all; the renderers are
    // only needed once a call is answered, and _preparePeerConnection sets
    // them up then. Tying the two together let a renderer problem stall
    // (re)connection, and with it every incoming call.
    await _loadIceServers(token);
    if (_disposed || generation != _generation || _token != token) return;

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
        _handleRaw,
        onDone: () => _onSocketClosed(generation),
        onError: (_) => _onSocketClosed(generation),
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
      _subscription = null;
      _scheduleReconnect();
    }
    _notify();
  }

  /// Sign-out: end any call, close the socket and stop reconnecting.
  Future<void> disconnect() async {
    _token = null;
    _username = null;
    _cancelReconnect();
    _reconnectAttempts = 0;
    if (inCall) await hangUp();
    final subscription = _subscription;
    final channel = _channel;
    _generation++;
    _connecting = null;
    _subscription = null;
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    await subscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {}
    _notify();
  }

  void _closeChannel() {
    _generation++;
    _connecting = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (channel != null) {
      unawaited(Future<void>.sync(() => channel.sink.close())
          .catchError((Object _) {}));
    }
  }

  void _onSocketClosed(int generation) {
    // A socket that has already been replaced must not disturb its successor.
    if (generation != _generation) return;
    _channel = null;
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (inCall) _fail("The connection dropped.");
    // Without this a dropped socket left the traveller unreachable for
    // incoming calls until they signed out and back in.
    _scheduleReconnect();
    _notify();
  }

  void _scheduleReconnect() {
    if (_disposed || _token == null || _reconnectTimer != null) return;
    final seconds = math.min(30, 1 << math.min(_reconnectAttempts, 5));
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      ensureConnected();
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _loadIceServers(String token) async {
    try {
      final response = await httpGet(
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
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      // A closing socket reports itself through onDone/onError.
    }
  }

  // ---------------------------------------------------------------------
  // Inbound frames
  // ---------------------------------------------------------------------

  /// Run a frame handler, ending the call cleanly if it throws.
  ///
  /// Handlers await media and SDP operations. Their failures used to vanish
  /// inside the stream listener, leaving both sides stuck on "connecting".
  void _handleRaw(dynamic raw) {
    final generation = _callGeneration;
    unawaited(_onFrame(raw).catchError((Object error) {
      if (error is _CallCancelled || generation != _callGeneration) return;
      _abortCall("The call could not connect.");
    }));
  }

  /// Whether [message] belongs to the call in progress.
  ///
  /// Without this a hangup or ICE candidate for a different call (say, one
  /// declined because the line was busy) could tear down the current call.
  bool _isCurrentCall(Map<String, dynamic> message) {
    final session = _session;
    return session != null &&
        session.callId.isNotEmpty &&
        message["call_id"]?.toString() == session.callId;
  }

  Future<void> _onFrame(dynamic raw) async {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (message["type"]) {
      case "ready":
        _reconnectAttempts = 0;
        break;
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
        await _onHangup(message);
        break;
      case "error":
        // Errors carry no call id. Only a call still being set up can have
        // caused one; anything later is a reply to a stale frame and must not
        // end the call in progress.
        if (_stage == CallStage.dialling || _stage == CallStage.connecting) {
          _abortCall(message["error"]?.toString() ?? "Call failed.");
        }
        break;
    }
  }

  Future<void> _onHangup(Map<String, dynamic> message) async {
    if (!_isCurrentCall(message)) return;
    final incoming = _session?.incoming ?? false;
    String? reason;
    switch (message["reason"]) {
      case "decline":
        reason = incoming ? null : "Call declined.";
        break;
      case "timeout":
        reason = incoming ? null : "No answer.";
        break;
      case "unavailable":
        reason = incoming
            ? "This call is no longer available."
            : "No one is available to take this call right now.";
        break;
      case "disconnect":
        reason = "The other person lost their connection.";
        break;
      // "answered_elsewhere" and a normal hangup end quietly.
    }
    await _teardown(reason);
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
    // Only the reply to our own pending request; never re-key a live call.
    if (session == null ||
        _stage != CallStage.dialling ||
        session.callId.isNotEmpty) {
      return;
    }

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
    final callId = message["call_id"]?.toString() ?? "";
    if (callId.isEmpty) return;
    // Already busy: decline rather than leaving the caller ringing forever.
    if (inCall) {
      if (_session?.callId != callId) {
        _send({"type": "decline", "call_id": callId});
      }
      return;
    }

    _session = CallSession(
      callId: callId,
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
    if (session == null ||
        session.incoming ||
        !_isCurrentCall(message) ||
        _stage != CallStage.ringing) {
      return;
    }

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

    try {
      await _preparePeerConnection(video: session.video);
    } on _CallCancelled {
      return;
    } catch (_) {
      // Without this the callee waited on a caller that could never send an
      // offer, because the caller's microphone had been refused.
      _abortCall("Microphone or camera permission was refused.");
      return;
    }
    final connection = _peerConnection;
    if (connection == null || _session?.callId != session.callId) return;
    _startConnectTimer();

    final offer = await connection.createOffer();
    if (!identical(_peerConnection, connection)) return;
    await connection.setLocalDescription(offer);
    if (!identical(_peerConnection, connection)) return;
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
    if (session == null ||
        !session.incoming ||
        !_isCurrentCall(message) ||
        _remoteDescriptionSet) {
      return;
    }

    await _preparePeerConnection(video: session.video);
    final connection = _peerConnection;
    if (connection == null) return;

    await connection.setRemoteDescription(RTCSessionDescription(
      message["sdp"]?.toString(),
      message["sdp_type"]?.toString() ?? "offer",
    ));
    if (!identical(_peerConnection, connection)) return;
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await connection.createAnswer();
    if (!identical(_peerConnection, connection)) return;
    await connection.setLocalDescription(answer);
    if (!identical(_peerConnection, connection)) return;
    _send({
      "type": "answer",
      "call_id": session.callId,
      "to": message["from"]?.toString() ?? session.peer,
      "sdp": answer.sdp,
      "sdp_type": answer.type,
    });
    // The stage becomes active only when media actually connects; finishing
    // SDP used to show "in call" for calls that never carried any audio.
  }

  Future<void> _onAnswer(Map<String, dynamic> message) async {
    final session = _session;
    if (session == null ||
        session.incoming ||
        !_isCurrentCall(message) ||
        _remoteDescriptionSet) {
      return;
    }
    final connection = _peerConnection;
    if (connection == null) return;

    await connection.setRemoteDescription(RTCSessionDescription(
      message["sdp"]?.toString(),
      message["sdp_type"]?.toString() ?? "answer",
    ));
    if (!identical(_peerConnection, connection)) return;
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();
  }

  Future<void> _onRemoteCandidate(Map<String, dynamic> message) async {
    if (!_isCurrentCall(message)) return;
    final value = message["candidate"]?.toString();
    if (value == null || value.isEmpty) return;
    final candidate = RTCIceCandidate(
      value,
      message["sdp_mid"]?.toString(),
      (message["sdp_m_line_index"] as num?)?.toInt(),
    );

    final connection = _peerConnection;
    if (!_remoteDescriptionSet || connection == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    try {
      await connection.addCandidate(candidate);
    } catch (_) {
      // One unusable candidate must not end a call others can carry.
    }
  }

  Future<void> _flushPendingCandidates() async {
    final pending = List<RTCIceCandidate>.of(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in pending) {
      final connection = _peerConnection;
      if (connection == null) return;
      try {
        await connection.addCandidate(candidate);
      } catch (_) {}
    }
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

  /// Open media and the peer connection once per call.
  ///
  /// Concurrent callers share one attempt. If the call ends while the
  /// permission prompt is open, the late stream is released rather than left
  /// holding the microphone, and [_CallCancelled] is thrown.
  Future<void> _preparePeerConnection({required bool video}) {
    if (_peerConnection != null) return Future<void>.value();
    final existing = _preparing;
    if (existing != null) return existing;
    late final Future<void> attempt;
    attempt = _createPeerConnection(video: video, generation: _callGeneration)
        .whenComplete(() {
      if (identical(_preparing, attempt)) _preparing = null;
    });
    _preparing = attempt;
    return attempt;
  }

  Future<void> _createPeerConnection({
    required bool video,
    required int generation,
  }) async {
    void checkCurrent() {
      if (generation != _callGeneration) throw const _CallCancelled();
    }

    try {
      await _ensureRenderers();
      checkCurrent();

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
      if (generation != _callGeneration) {
        await _disposeStream(stream);
        throw const _CallCancelled();
      }
      _localStream = stream;
      localRenderer.srcObject = stream;

      final connection = await createPeerConnection({
        "iceServers": _iceServers,
        "sdpSemantics": "unified-plan",
      });
      if (generation != _callGeneration) {
        try {
          await connection.close();
        } catch (_) {}
        throw const _CallCancelled();
      }
      // Published before any further await, so a teardown can close it.
      _peerConnection = connection;
      _attachHandlers(connection);

      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
        checkCurrent();
      }

      _cameraOff = !video;
      _notify();
    } catch (error) {
      if (generation != _callGeneration) throw const _CallCancelled();
      rethrow;
    }
  }

  void _attachHandlers(RTCPeerConnection connection) {
    connection.onIceCandidate = (candidate) {
      final session = _session;
      if (!identical(_peerConnection, connection) ||
          session == null ||
          candidate.candidate == null) {
        return;
      }
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
      if (!identical(_peerConnection, connection)) return;
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        _notify();
      }
    };

    // Not every platform reports the aggregate connection state, so the ICE
    // state is watched as well; whichever reports first wins.
    connection.onConnectionState = (state) {
      if (!identical(_peerConnection, connection)) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markActive();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _abortCall(_noMediaMessage);
      }
    };
    connection.onIceConnectionState = (state) {
      if (!identical(_peerConnection, connection)) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markActive();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _abortCall(_noMediaMessage);
      }
    };
  }

  /// Without a TURN relay a failed connection is the expected outcome on any
  /// network that uses symmetric NAT, which most mobile carriers do.
  String get _noMediaMessage => _hasTurn
      ? "The call could not connect."
      : "The call could not connect. This often happens on mobile "
          "data — try again on Wi-Fi.";

  void _markActive() {
    _connectTimer?.cancel();
    _connectTimer = null;
    if (_stage == CallStage.connecting) {
      _stage = CallStage.active;
      _notify();
    }
  }

  /// Bound the time between answering and media flowing. Started after the
  /// permission prompt, so a slow tap on "Allow" does not count against it.
  void _startConnectTimer() {
    _connectTimer?.cancel();
    final generation = _callGeneration;
    _connectTimer = Timer(connectTimeout, () {
      if (generation != _callGeneration || _stage != CallStage.connecting) {
        return;
      }
      _abortCall(_noMediaMessage);
    });
  }

  Future<void> _disposeStream(MediaStream stream) async {
    try {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    } catch (_) {}
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
    if (session == null || !session.incoming || _stage != CallStage.ringing) {
      return;
    }

    _stage = CallStage.connecting;
    _notify();

    // Media is opened before accepting so that, if permission is refused, the
    // caller is declined cleanly instead of connecting to silence.
    try {
      await _preparePeerConnection(video: session.video);
    } on _CallCancelled {
      return;
    } catch (_) {
      if (_session?.callId != session.callId) return;
      _send({"type": "decline", "call_id": session.callId});
      _fail("Microphone or camera permission was refused.");
      return;
    }

    // The caller may have given up while the permission prompt was open.
    if (_session?.callId != session.callId || _stage != CallStage.connecting) {
      return;
    }
    _send({"type": "accept", "call_id": session.callId});
    _startConnectTimer();
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

  /// End the current call locally and tell the other side, so neither device
  /// is left waiting on a call that can no longer connect.
  void _abortCall(String message) {
    final session = _session;
    if (session == null) return;
    if (session.callId.isNotEmpty) {
      _send({"type": "hangup", "call_id": session.callId});
    }
    _fail(message);
  }

  /// Release everything the current call holds. Safe to call repeatedly:
  /// state is cleared synchronously, before any await, so a second caller
  /// finds nothing left to release and cannot overwrite the first reason.
  Future<void> _teardown(String? message) async {
    final session = _session;
    final stream = _localStream;
    final connection = _peerConnection;
    if (session == null && stream == null && connection == null) {
      if (message != null) _error = message;
      _notify();
      return;
    }

    _callGeneration++;
    _ringTimer?.cancel();
    _ringTimer = null;
    _connectTimer?.cancel();
    _connectTimer = null;
    _preparing = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _localStream = null;
    _peerConnection = null;

    if (_renderersReady && !_disposed) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }

    _muted = false;
    _cameraOff = false;
    _error = message;
    _stage = session == null ? CallStage.idle : CallStage.ended;
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

    if (stream != null) await _disposeStream(stream);
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {}
    }
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
    _connectTimer?.cancel();
    _reconnectTimer?.cancel();
    _callGeneration++;
    _generation++;
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
