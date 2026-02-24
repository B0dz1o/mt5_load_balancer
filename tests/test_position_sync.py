"""
tests/test_position_sync.py – Unit tests for volume scaling and sync-diff logic.

These tests verify scale_volume(), compute_sync_diff(),
build_position_snapshot(), and parse_position_snapshot() – all of which
mirror the logic in MQL5/Include/LoadBalancer/PositionSync.mqh and
MQL5/Experts/LoadBalancer/LoadBalancerSlave.mq5.
"""

import pytest

from lb_core import (
    PositionSnapshot,
    build_position_snapshot,
    compute_sync_diff,
    parse_position_snapshot,
    scale_volume,
)

# ---------------------------------------------------------------------------
# scale_volume
# ---------------------------------------------------------------------------

class TestScaleVolume:
    def test_full_ratio(self):
        assert scale_volume(1.0, 1.0) == 1.0

    def test_70_percent_ratio(self):
        # 2.0 * 0.70 = 1.40, step=0.01 → 1.40
        assert scale_volume(2.0, 0.70) == 1.40

    def test_rounds_down_to_step(self):
        # 1.0 * 0.33 = 0.33 → floor to nearest 0.01 = 0.33
        result = scale_volume(1.0, 0.33, volume_step=0.01)
        assert result == pytest.approx(0.33, abs=1e-7)

    def test_fractional_step(self):
        # step = 0.1, 1.0 * 0.75 = 0.75 → floor to 0.7
        result = scale_volume(1.0, 0.75, volume_step=0.1)
        assert result == pytest.approx(0.7, abs=1e-7)

    def test_clamps_to_minimum(self):
        # 0.01 * 0.001 = 0.00001, below min_volume of 0.01
        result = scale_volume(0.01, 0.001, volume_min=0.01)
        assert result == pytest.approx(0.01, abs=1e-7)

    def test_clamps_to_maximum(self):
        result = scale_volume(200.0, 1.0, volume_max=100.0)
        assert result == pytest.approx(100.0, abs=1e-7)

    def test_zero_ratio_returns_minimum(self):
        # 0 * anything = 0, clamped to volume_min
        result = scale_volume(1.0, 0.0, volume_min=0.01)
        assert result == pytest.approx(0.01, abs=1e-7)

    def test_large_volume_with_small_step(self):
        result = scale_volume(10.0, 0.5, volume_step=0.01)
        assert result == pytest.approx(5.0, abs=1e-7)

    def test_step_guard_against_zero(self):
        # If step is 0 it should default to 0.01 internally and not divide-by-zero
        result = scale_volume(1.0, 1.0, volume_step=0)
        assert result > 0

    def test_returns_float(self):
        assert isinstance(scale_volume(1.0, 0.5), float)


# ---------------------------------------------------------------------------
# build_position_snapshot / parse_position_snapshot
# ---------------------------------------------------------------------------

class TestPositionSnapshot:
    def test_empty_list(self):
        snap = build_position_snapshot([])
        assert snap == "[]"
        assert parse_position_snapshot(snap) == []

    def test_roundtrip_single(self):
        positions = [PositionSnapshot("EURUSD", 0, 1.0, 1.05, 1.12)]
        snap = build_position_snapshot(positions)
        parsed = parse_position_snapshot(snap)
        assert len(parsed) == 1
        assert parsed[0].symbol == "EURUSD"
        assert parsed[0].type   == 0
        assert parsed[0].vol    == pytest.approx(1.0)
        assert parsed[0].sl     == pytest.approx(1.05)
        assert parsed[0].tp     == pytest.approx(1.12)

    def test_roundtrip_multiple(self, master_positions):
        snap   = build_position_snapshot(master_positions)
        parsed = parse_position_snapshot(snap)
        assert len(parsed) == len(master_positions)
        symbols = {p.symbol for p in parsed}
        assert "EURUSD" in symbols
        assert "GBPUSD" in symbols

    def test_parse_invalid_json_returns_empty(self):
        assert parse_position_snapshot("not json") == []

    def test_parse_none_returns_empty(self):
        assert parse_position_snapshot(None) == []

    def test_volume_rounded_to_2dp(self):
        positions = [PositionSnapshot("XAUUSD", 0, 1.123456789)]
        snap = build_position_snapshot(positions)
        parsed = parse_position_snapshot(snap)
        # vol field is stored as 2 dp in snapshot
        assert parsed[0].vol == pytest.approx(1.12, abs=1e-2)

    def test_sell_position_type(self):
        positions = [PositionSnapshot("USDJPY", 1, 0.5)]
        parsed = parse_position_snapshot(build_position_snapshot(positions))
        assert parsed[0].type == 1


# ---------------------------------------------------------------------------
# compute_sync_diff
# ---------------------------------------------------------------------------

class TestComputeSyncDiff:
    def test_no_diff_when_in_sync(self):
        master = [PositionSnapshot("EURUSD", 0, 1.0)]
        slave  = [PositionSnapshot("EURUSD", 0, 1.0)]
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert diffs == []

    def test_open_missing_position(self):
        master = [PositionSnapshot("EURUSD", 0, 1.0)]
        slave  = []
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert len(diffs) == 1
        assert diffs[0].action == "open"
        assert diffs[0].symbol == "EURUSD"
        assert diffs[0].volume == pytest.approx(1.0)

    def test_close_orphan_position(self):
        master = []
        slave  = [PositionSnapshot("GBPUSD", 1, 0.5)]
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert len(diffs) == 1
        assert diffs[0].action == "close"
        assert diffs[0].symbol == "GBPUSD"

    def test_adjust_add_when_volume_too_low(self):
        master = [PositionSnapshot("EURUSD", 0, 2.0)]
        slave  = [PositionSnapshot("EURUSD", 0, 1.0)]
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert len(diffs) == 1
        assert diffs[0].action == "adjust_add"
        assert diffs[0].volume == pytest.approx(1.0)

    def test_adjust_reduce_when_volume_too_high(self):
        master = [PositionSnapshot("EURUSD", 0, 1.0)]
        slave  = [PositionSnapshot("EURUSD", 0, 2.0)]
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert len(diffs) == 1
        assert diffs[0].action == "adjust_reduce"
        assert diffs[0].volume == pytest.approx(1.0)

    def test_ratio_applied_to_open(self):
        master = [PositionSnapshot("EURUSD", 0, 2.0)]
        slave  = []
        diffs  = compute_sync_diff(master, slave, ratio=0.5)
        assert len(diffs) == 1
        assert diffs[0].action == "open"
        assert diffs[0].volume == pytest.approx(1.0)

    def test_ratio_applied_to_adjust(self):
        master = [PositionSnapshot("EURUSD", 0, 4.0)]
        slave  = [PositionSnapshot("EURUSD", 0, 1.0)]
        # target = 4.0 * 0.5 = 2.0; slave has 1.0 → add 1.0
        diffs  = compute_sync_diff(master, slave, ratio=0.5)
        assert len(diffs) == 1
        assert diffs[0].action == "adjust_add"
        assert diffs[0].volume == pytest.approx(1.0)

    def test_mixed_scenario(self, master_positions, slave_positions):
        # master: EURUSD BUY 2.0, GBPUSD SELL 1.0
        # slave:  EURUSD BUY 1.40, USDJPY BUY 0.5
        diffs = compute_sync_diff(master_positions, slave_positions, ratio=1.0)
        actions = {d.action for d in diffs}
        symbols = {d.symbol for d in diffs}
        assert "open"  in actions     # GBPUSD missing on slave
        assert "close" in actions     # USDJPY orphan on slave
        assert "adjust_add" in actions  # EURUSD volume mismatch
        assert "GBPUSD" in symbols
        assert "USDJPY" in symbols
        assert "EURUSD" in symbols

    def test_below_step_threshold_ignored(self):
        # Difference smaller than volume_step must not generate an action
        master = [PositionSnapshot("EURUSD", 0, 1.0)]
        slave  = [PositionSnapshot("EURUSD", 0, 1.009)]  # diff = 0.009 < step 0.01
        diffs  = compute_sync_diff(master, slave, ratio=1.0, volume_step=0.01)
        assert diffs == []

    def test_empty_master_and_slave(self):
        assert compute_sync_diff([], [], ratio=1.0) == []

    def test_position_type_preserved_in_action(self):
        master = [PositionSnapshot("USDJPY", 1, 1.0)]  # SELL
        slave  = []
        diffs  = compute_sync_diff(master, slave, ratio=1.0)
        assert diffs[0].position_type == 1

    def test_open_action_volume_below_min_skipped(self):
        # If the scaled volume is below volume_min, no "open" should be emitted
        # (scale_volume clamps to volume_min, so the open action appears but with min vol)
        master = [PositionSnapshot("EURUSD", 0, 0.01)]
        slave  = []
        diffs  = compute_sync_diff(master, slave, ratio=0.001,
                                   volume_min=0.01, volume_step=0.01)
        # scale_volume clamps to 0.01 minimum, so an "open" IS generated
        assert len(diffs) == 1
        assert diffs[0].volume == pytest.approx(0.01)
