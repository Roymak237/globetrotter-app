"""Isolated signalling regressions: fake sockets, mocked stores, no server/data writes."""
import importlib.util
import inspect
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
try:
    from app import models
    spec = importlib.util.spec_from_file_location("isolated_calls", BACKEND / "app/calls.py")
    assert spec is not None and spec.loader is not None
    calls = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(calls)
finally:
    sys.path.pop(0)


class FakeSocket:
    def __init__(self):
        self.frames = []
        self.fail = False

    def send(self, body):
        if self.fail:
            raise OSError("closed test socket")
        self.frames.append(json.loads(body))


class CallTests(unittest.TestCase):
    def setUp(self):
        calls._CONNECTIONS.clear()
        calls._ACTIVE_CALLS.clear()
        self.room = {"id": "room", "type": "group", "members": ["alice", "bob", "carol"]}
        self.users = {name: {"username": name, "blocked": [], "session_version": 0}
                      for name in ["alice", "bob", "carol", "outsider"]}
        self.saved = {}
        self.updates = []
        self.addCleanup(patch.stopall)
        patch.object(models, "_write_json", side_effect=AssertionError("real store write forbidden")).start()
        patch.object(calls, "get_room_by_id", side_effect=lambda _: self.room).start()
        patch.object(calls, "get_user_by_username", side_effect=self.users.get).start()
        patch.object(calls, "save_call", side_effect=lambda r: self.saved.update({r["id"]: dict(r)})).start()
        patch.object(calls, "save_notification").start()
        patch.object(calls, "update_call", side_effect=self.update_record).start()
        self.alice = self.connect("alice")
        self.alice_tab = self.connect("alice")
        self.bob = self.connect("bob")
        self.bob_tab = self.connect("bob")
        self.carol = self.connect("carol")
        self.outsider = self.connect("outsider")

    def tearDown(self):
        for state in calls._ACTIVE_CALLS.values():
            timer = state.get("timer")
            if timer is not None:
                timer.cancel()
        calls._ACTIVE_CALLS.clear()
        calls._CONNECTIONS.clear()

    def update_record(self, call_id, changes):
        self.updates.append((call_id, dict(changes)))
        self.saved[call_id].update(changes)

    def connect(self, username):
        ws = FakeSocket()
        calls._register(username, ws)
        return ws

    def handle(self, username, ws, kind, **fields):
        message = {"type": kind, **fields}
        # Baseline compatibility lets these regressions demonstrate the old bugs.
        if "ws" in inspect.signature(calls._handle).parameters:
            reply = calls._handle(username, message, ws)
        else:
            reply = calls._handle(username, message)
        if reply is not None:
            ws.send(json.dumps(reply))
        return reply

    def begin(self):
        self.handle("alice", self.alice, "call", room_id="room")
        return next(f["call_id"] for f in reversed(self.alice.frames) if f["type"] == "ringing")

    def test_outsider_cannot_hang_up(self):
        call_id = self.begin()
        self.handle("outsider", self.outsider, "hangup", call_id=call_id)
        self.assertIn(call_id, calls._ACTIVE_CALLS)

    def test_one_group_decline_does_not_end_call(self):
        call_id = self.begin()
        self.handle("carol", self.carol, "decline", call_id=call_id)
        self.assertIn(call_id, calls._ACTIVE_CALLS)

    def test_first_accept_only_reaches_caller_socket(self):
        call_id = self.begin()
        self.handle("bob", self.bob, "accept", call_id=call_id)
        self.handle("carol", self.carol, "accept", call_id=call_id)
        accepted = [f for f in self.alice.frames if f["type"] == "accepted"]
        self.assertEqual([f["by"] for f in accepted], ["bob"])
        self.assertEqual(self.alice_tab.frames, [])
        self.assertEqual(self.bob_tab.frames[-1].get("reason"), "answered_elsewhere")

    def test_zero_reached_is_finalized(self):
        calls._unregister("bob", self.bob)
        calls._unregister("bob", self.bob_tab)
        calls._unregister("carol", self.carol)
        call_id = self.begin()
        self.assertNotIn(call_id, calls._ACTIVE_CALLS)
        self.assertEqual(self.saved[call_id]["status"], "missed")
        self.assertIsNotNone(self.saved[call_id]["ended_at"])


if __name__ == "__main__":
    unittest.main()