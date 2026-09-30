import "dart:async";
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/services/call_service.dart";
import "package:web_socket_channel/web_socket_channel.dart";

/// A signalling socket that never touches the network.
///
/// CallService opens its own socket, so without a seam the entire call
/// lifecycle is untestable — which is how a caller could be left ringing at a
/// call that had already failed without a single test noticing.
class _FakeSocket implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(sent, _incoming);

  /// Push a frame as though the server had sent it.
  void emit(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));

  /// Frames the service sent, by type.
  List<Map<String, dynamic>> sentOfType(String type) =>
      sent.where((frame) => frame["type"] == type).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSink implements WebSocketSink {
  final List<Map<String, dynamic>> _sent;
  final StreamController<dynamic> _incoming;

  _FakeSink(this._sent, this._incoming);

  @override
  void add(dynamic data) =>
      _sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<CallService> _connected(_FakeSocket socket) async {
  final service = CallService()..channelFactory = (_) => socket;
  await service.connect("test-token", "alice");
  return service;
}

/// Let the socket's broadcast stream deliver and the handler run.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group("A call that reaches nobody", () {
    test("fails instead of ringing forever", () async {
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      expect(service.stage, CallStage.dialling);

      // This is exactly what the real server replies when the person being
      // called has no open socket — confirmed against a live backend, which
      // then sends nothing further at all.
      socket.emit({
        "type": "ringing",
        "call_id": "call-1",
        "room_id": "room-1",
        "video": false,
        "reached": 0,
      });
      await _settle();

      expect(
        service.stage,
        isNot(CallStage.ringing),
        reason: "the call already failed; showing 'ringing' is a lie that "
            "never resolves, which is what 'calls are not going through' was",
      );
      expect(service.error, isNotNull);
      expect(service.inCall, isFalse);
    });

    test("says who could not be reached rather than failing silently",
        () async {
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      socket.emit({"type": "ringing", "call_id": "c", "reached": 0});
      await _settle();

      expect(service.error, isNotEmpty);
      expect(service.error!.toLowerCase(), contains("online"));
    });
  });

  group("A call that does reach someone", () {
    test("rings", () async {
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      socket.emit({
        "type": "ringing",
        "call_id": "call-1",
        "room_id": "room-1",
        "video": false,
        "reached": 1,
      });
      await _settle();

      expect(service.stage, CallStage.ringing);
      expect(service.error, isNull);
      expect(service.session?.callId, "call-1");
    });

    test("carries the call id the server assigned", () async {
      // The id is generated server-side, and every later frame — accept,
      // hangup, ICE — is rejected without it. Keeping the placeholder would
      // make the call unreachable by its own participants.
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      expect(service.session?.callId, isEmpty);

      socket.emit({"type": "ringing", "call_id": "server-id", "reached": 1});
      await _settle();

      expect(service.session?.callId, "server-id");

      await service.hangUp();
      expect(
        socket.sentOfType("hangup").single["call_id"],
        "server-id",
        reason: "hanging up with the placeholder id would leave the call "
            "ringing on the other device",
      );
    });
  });

  group("Declining and hanging up", () {
    test("a decline from the other side ends the call with a reason", () async {
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      socket.emit({"type": "ringing", "call_id": "c1", "reached": 1});
      await _settle();
      socket.emit({"type": "hangup", "call_id": "c1", "reason": "decline"});
      await _settle();

      expect(service.inCall, isFalse);
      expect(service.error, contains("declined"));
    });

    test("a server error is surfaced rather than swallowed", () async {
      final socket = _FakeSocket();
      final service = await _connected(socket);
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );
      socket.emit({"type": "error", "error": "you are not a member"});
      await _settle();

      expect(service.error, "you are not a member");
      expect(service.inCall, isFalse);
    });
  });

  group("Calling while offline", () {
    test("does not silently do nothing", () async {
      // No channelFactory override and no connect(), so there is no socket.
      final service = CallService();
      addTearDown(service.dispose);

      await service.startCall(
        roomId: "room-1",
        peer: "bob",
        peerDisplayName: "Bob",
      );

      expect(service.error, isNotNull);
      expect(service.inCall, isFalse);
    });
  });
}
