"""
lb_core.py – Python mirror of the core MQL5 Load Balancer algorithms.

These functions replicate the pure logic from:
  MQL5/Include/LoadBalancer/TradeSignal.mqh
  MQL5/Include/LoadBalancer/PositionSync.mqh
  MQL5/Include/LoadBalancer/Notifications.mqh

They exist so that the CI pipeline can unit-test the business logic without
requiring a live MetaTrader 5 terminal.
"""

from __future__ import annotations

import json
import math
import random
import time
from dataclasses import dataclass
from enum import IntEnum
from typing import Optional

# ---------------------------------------------------------------------------
# Constants (mirrors Config.mqh)
# ---------------------------------------------------------------------------

SYNC_MODE_PERIODIC = 0
SYNC_MODE_HOOKS    = 1
SYNC_MODE_BOTH     = 2

DEFAULT_SYNC_INTERVAL_SEC = 300
DEFAULT_RATIO             = 1.0
MAX_SIGNAL_FILES          = 1000

DEFAULT_SIGNAL_DIR   = "LoadBalancer/signals/"
SIGNAL_FILE_PREFIX   = "sig_"
SIGNAL_FILE_EXT      = ".json"
PROCESSED_FILE_EXT   = ".done"

NOTIFY_ALERT = 0x01
NOTIFY_PRINT = 0x02
NOTIFY_PUSH  = 0x04
NOTIFY_EMAIL = 0x08
NOTIFY_ALL   = 0x0F


# ---------------------------------------------------------------------------
# Signal action enum (mirrors ENUM_SIGNAL_ACTION in TradeSignal.mqh)
# ---------------------------------------------------------------------------

class SignalAction(IntEnum):
    BUY         = 0
    SELL        = 1
    BUY_LIMIT   = 2
    SELL_LIMIT  = 3
    BUY_STOP    = 4
    SELL_STOP   = 5
    CLOSE       = 6
    MODIFY      = 7
    SYNC_CHECK  = 8


# ---------------------------------------------------------------------------
# TradeSignal dataclass (mirrors TradeSignal struct in TradeSignal.mqh)
# ---------------------------------------------------------------------------

@dataclass
class TradeSignal:
    id:            str            = ""
    created_at:    int            = 0    # Unix timestamp
    action:        int            = 0    # SignalAction value
    symbol:        str            = ""
    master_volume: float          = 0.0
    price:         float          = 0.0
    sl:            float          = 0.0
    tp:            float          = 0.0
    master_ticket: int            = 0
    comment:       str            = ""
    # Slave-side fields (not written by master)
    processed:     bool           = False
    slave_account: str            = ""
    error_message: str            = ""


# ---------------------------------------------------------------------------
# Signal serialisation (mirrors SignalToJson / SignalFromJson in TradeSignal.mqh)
# ---------------------------------------------------------------------------

def signal_to_json(sig: TradeSignal) -> str:
    """Serialise a TradeSignal to a JSON string."""
    payload = {
        "id":            sig.id,
        "created_at":    sig.created_at,
        "action":        sig.action,
        "symbol":        sig.symbol,
        "master_volume": round(sig.master_volume, 8),
        "price":         round(sig.price, 8),
        "sl":            round(sig.sl, 8),
        "tp":            round(sig.tp, 8),
        "master_ticket": sig.master_ticket,
        "comment":       sig.comment,
    }
    return json.dumps(payload, indent=2)


def signal_from_json(raw: str) -> Optional[TradeSignal]:
    """Deserialise a TradeSignal from a JSON string. Returns None on error."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None

    sig = TradeSignal(
        id            = data.get("id", ""),
        created_at    = int(data.get("created_at", 0)),
        action        = int(data.get("action", 0)),
        symbol        = data.get("symbol", ""),
        master_volume = float(data.get("master_volume", 0.0)),
        price         = float(data.get("price", 0.0)),
        sl            = float(data.get("sl", 0.0)),
        tp            = float(data.get("tp", 0.0)),
        master_ticket = int(data.get("master_ticket", 0)),
        comment       = data.get("comment", ""),
    )
    if not sig.id:
        return None
    return sig


# ---------------------------------------------------------------------------
# Volume scaling (mirrors ScaleVolume in PositionSync.mqh)
# ---------------------------------------------------------------------------

def scale_volume(
    master_vol:  float,
    ratio:       float,
    volume_step: float = 0.01,
    volume_min:  float = 0.01,
    volume_max:  float = 100.0,
) -> float:
    """
    Apply the slave ratio to the master volume and round to the nearest
    volume step, clamped to [volume_min, volume_max].
    """
    if volume_step <= 0:
        volume_step = 0.01
    raw    = master_vol * ratio
    scaled = math.floor(raw / volume_step) * volume_step
    scaled = max(volume_min, min(volume_max, scaled))
    return round(scaled, 8)


# ---------------------------------------------------------------------------
# Signal ID generation (mirrors NewSignalId in PositionSync.mqh)
# ---------------------------------------------------------------------------

def new_signal_id() -> str:
    """Generate a unique signal ID (timestamp + random suffix)."""
    return f"{int(time.time())}_{random.randint(0, 99999):05d}"


# ---------------------------------------------------------------------------
# Position snapshot (mirrors BuildPositionSnapshot in LoadBalancerMaster.mq5)
# ---------------------------------------------------------------------------

@dataclass
class PositionSnapshot:
    symbol: str
    type:   int    # 0 = BUY, 1 = SELL
    vol:    float
    sl:     float = 0.0
    tp:     float = 0.0


def build_position_snapshot(positions: list[PositionSnapshot]) -> str:
    """Serialise a list of open positions into the compact JSON array used
    in SYNC_CHECK signal comments."""
    entries = [
        {"sym": p.symbol, "type": p.type, "vol": round(p.vol, 2),
         "sl": round(p.sl, 5), "tp": round(p.tp, 5)}
        for p in positions
    ]
    return json.dumps(entries)


def parse_position_snapshot(snapshot: str) -> list[PositionSnapshot]:
    """Parse the compact position snapshot back into PositionSnapshot objects."""
    try:
        data = json.loads(snapshot)
    except (json.JSONDecodeError, TypeError):
        return []
    result = []
    for entry in data:
        result.append(PositionSnapshot(
            symbol = entry.get("sym", ""),
            type   = int(entry.get("type", 0)),
            vol    = float(entry.get("vol", 0.0)),
            sl     = float(entry.get("sl", 0.0)),
            tp     = float(entry.get("tp", 0.0)),
        ))
    return result


# ---------------------------------------------------------------------------
# Sync diff calculation (core of HandleSyncCheck in LoadBalancerSlave.mq5)
# ---------------------------------------------------------------------------

@dataclass
class SyncAction:
    """Describes an adjustment the slave must make to match the master."""
    action:      str    # "open", "close", "adjust_add", "adjust_reduce"
    symbol:      str
    volume:      float
    position_type: int  # 0 = BUY, 1 = SELL


def compute_sync_diff(
    master_positions: list[PositionSnapshot],
    slave_positions:  list[PositionSnapshot],
    ratio:            float,
    volume_step:      float = 0.01,
    volume_min:       float = 0.01,
    volume_max:       float = 100.0,
) -> list[SyncAction]:
    """
    Compare master and slave position snapshots and return the list of
    SyncActions needed to bring the slave in line with the master.

    This is the Python equivalent of HandleSyncCheck() in LoadBalancerSlave.mq5.
    """
    actions: list[SyncAction] = []

    master_map = {p.symbol: p for p in master_positions}
    slave_map  = {p.symbol: p for p in slave_positions}

    # --- Positions that exist on master ---
    for sym, mp in master_map.items():
        target_vol = scale_volume(mp.vol, ratio, volume_step, volume_min, volume_max)

        if sym not in slave_map:
            # Position missing on slave → open it
            if target_vol >= volume_min:
                actions.append(SyncAction(
                    action        = "open",
                    symbol        = sym,
                    volume        = target_vol,
                    position_type = mp.type,
                ))
        else:
            sp   = slave_map[sym]
            diff = round(target_vol - sp.vol, 8)
            if abs(diff) >= volume_step:
                act = "adjust_add" if diff > 0 else "adjust_reduce"
                actions.append(SyncAction(
                    action        = act,
                    symbol        = sym,
                    volume        = abs(diff),
                    position_type = mp.type,
                ))

    # --- Slave-only positions (orphans) → close them ---
    for sym in slave_map:
        if sym not in master_map:
            actions.append(SyncAction(
                action        = "close",
                symbol        = sym,
                volume        = slave_map[sym].vol,
                position_type = slave_map[sym].type,
            ))

    return actions


# ---------------------------------------------------------------------------
# Notification formatting (mirrors NotifyFailure in Notifications.mqh)
# ---------------------------------------------------------------------------

def format_failure_message(
    account_login: str,
    action_str:    str,
    symbol:        str,
    error_msg:     str,
) -> str:
    """Format the failure notification string that would be shown as an
    Alert() / push notification on the slave terminal."""
    return (
        f"[LB Slave {account_login}] FAILED: {action_str} {symbol} — {error_msg}"
    )
