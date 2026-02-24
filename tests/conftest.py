"""
tests/conftest.py – shared pytest fixtures for the MT5 Load Balancer test suite.
"""

import pytest


@pytest.fixture
def basic_signal():
    """Return a fully populated TradeSignal for reuse across tests."""
    from lb_core import SignalAction, TradeSignal
    return TradeSignal(
        id            = "1700000000_12345",
        created_at    = 1700000000,
        action        = int(SignalAction.BUY),
        symbol        = "EURUSD",
        master_volume = 1.0,
        price         = 0.0,
        sl            = 1.0500,
        tp            = 1.1200,
        master_ticket = 987654,
        comment       = "test",
    )


@pytest.fixture
def master_positions():
    """Return a sample list of master PositionSnapshots."""
    from lb_core import PositionSnapshot
    return [
        PositionSnapshot(symbol="EURUSD", type=0, vol=2.0, sl=1.05, tp=1.12),
        PositionSnapshot(symbol="GBPUSD", type=1, vol=1.0, sl=1.30, tp=1.25),
    ]


@pytest.fixture
def slave_positions():
    """Return a sample list of slave PositionSnapshots (slightly out of sync)."""
    from lb_core import PositionSnapshot
    return [
        PositionSnapshot(symbol="EURUSD", type=0, vol=1.40, sl=1.05, tp=1.12),
        PositionSnapshot(symbol="USDJPY", type=0, vol=0.5,  sl=0.0,  tp=0.0),
    ]
