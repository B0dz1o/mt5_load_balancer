"""
tests/test_trade_signal.py – Unit tests for TradeSignal serialisation/deserialisation.

These tests verify that signal_to_json() and signal_from_json() are symmetric
and handle edge cases correctly, mirroring the behaviour of
MQL5/Include/LoadBalancer/TradeSignal.mqh.
"""

from lb_core import (
    SignalAction,
    TradeSignal,
    new_signal_id,
    signal_from_json,
    signal_to_json,
)


class TestSignalToJson:
    def test_produces_valid_json(self, basic_signal):
        import json
        raw = signal_to_json(basic_signal)
        data = json.loads(raw)   # must not raise
        assert isinstance(data, dict)

    def test_all_fields_present(self, basic_signal):
        import json
        data = json.loads(signal_to_json(basic_signal))
        for key in ("id", "created_at", "action", "symbol", "master_volume",
                    "price", "sl", "tp", "master_ticket", "comment"):
            assert key in data, f"Missing key: {key}"

    def test_values_are_preserved(self, basic_signal):
        import json
        data = json.loads(signal_to_json(basic_signal))
        assert data["id"]            == basic_signal.id
        assert data["symbol"]        == basic_signal.symbol
        assert data["action"]        == basic_signal.action
        assert data["master_volume"] == basic_signal.master_volume
        assert data["sl"]            == basic_signal.sl
        assert data["tp"]            == basic_signal.tp
        assert data["master_ticket"] == basic_signal.master_ticket

    def test_slave_fields_not_serialised(self, basic_signal):
        """processed / slave_account / error_message are slave-side only."""
        import json
        data = json.loads(signal_to_json(basic_signal))
        assert "processed"     not in data
        assert "slave_account" not in data
        assert "error_message" not in data

    def test_volume_precision(self):
        sig = TradeSignal(id="x", master_volume=0.123456789)
        import json
        data = json.loads(signal_to_json(sig))
        # Must be rounded to 8 decimal places
        assert len(str(data["master_volume"]).split(".")[-1]) <= 8


class TestSignalFromJson:
    def test_roundtrip(self, basic_signal):
        raw    = signal_to_json(basic_signal)
        parsed = signal_from_json(raw)
        assert parsed is not None
        assert parsed.id            == basic_signal.id
        assert parsed.symbol        == basic_signal.symbol
        assert parsed.action        == basic_signal.action
        assert parsed.master_volume == basic_signal.master_volume
        assert parsed.sl            == basic_signal.sl
        assert parsed.tp            == basic_signal.tp
        assert parsed.master_ticket == basic_signal.master_ticket
        assert parsed.comment       == basic_signal.comment

    def test_returns_none_on_invalid_json(self):
        assert signal_from_json("not json at all") is None

    def test_returns_none_on_missing_id(self):
        import json
        data = {"action": 0, "symbol": "EURUSD"}
        assert signal_from_json(json.dumps(data)) is None

    def test_returns_none_on_empty_string(self):
        assert signal_from_json("") is None

    def test_defaults_for_missing_optional_fields(self):
        import json
        data = {"id": "abc123", "action": 1, "symbol": "GBPUSD"}
        sig = signal_from_json(json.dumps(data))
        assert sig is not None
        assert sig.master_volume == 0.0
        assert sig.sl == 0.0
        assert sig.tp == 0.0
        assert sig.master_ticket == 0

    def test_all_signal_actions_roundtrip(self):
        for action in SignalAction:
            sig = TradeSignal(id="id1", action=int(action), symbol="USDJPY",
                              master_volume=1.0)
            parsed = signal_from_json(signal_to_json(sig))
            assert parsed is not None
            assert parsed.action == int(action)

    def test_slave_fields_initialised_correctly(self, basic_signal):
        parsed = signal_from_json(signal_to_json(basic_signal))
        assert not parsed.processed
        assert parsed.slave_account == ""
        assert parsed.error_message == ""

    def test_empty_comment_preserved(self):
        sig = TradeSignal(id="id_empty", comment="")
        parsed = signal_from_json(signal_to_json(sig))
        assert parsed.comment == ""

    def test_comment_with_special_chars(self):
        sig = TradeSignal(id="id_special", comment='sync: "test" & <ok>')
        parsed = signal_from_json(signal_to_json(sig))
        assert parsed is not None
        assert parsed.comment == sig.comment


class TestNewSignalId:
    def test_returns_string(self):
        assert isinstance(new_signal_id(), str)

    def test_ids_are_unique(self):
        ids = {new_signal_id() for _ in range(100)}
        # With timestamp + random suffix, collisions are practically impossible
        assert len(ids) > 1

    def test_format(self):
        sid = new_signal_id()
        parts = sid.split("_")
        assert len(parts) == 2
        assert parts[0].isdigit()
        assert parts[1].isdigit()
