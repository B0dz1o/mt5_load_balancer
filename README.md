# mt5_load_balancer

**MQL5-based tool to make secondary MT5 accounts mimic a primary one.**  
Distribute risk and save on fees by keeping multiple broker accounts in sync — automatically.

[![CI](https://github.com/B0dz1o/mt5_load_balancer/actions/workflows/ci.yml/badge.svg)](https://github.com/B0dz1o/mt5_load_balancer/actions/workflows/ci.yml)

---

## Table of Contents

1. [Overview](#overview)
2. [How it works](#how-it-works)
3. [Project structure](#project-structure)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Sync modes](#sync-modes)
7. [Volume ratio](#volume-ratio)
8. [Failure notifications](#failure-notifications)
9. [Development & testing](#development--testing)
10. [Contributing](#contributing)

---

## Overview

You have **one primary account** (broker A) that you trade actively.  
You want **one or more secondary accounts** (brokers B, C, D…) to mirror the same portfolio,
optionally at a scaled-down volume (e.g. 70 % of the primary).

`mt5_load_balancer` consists of two MetaTrader 5 Expert Advisors:

| EA | Account | Role |
|----|---------|------|
| `LoadBalancerMaster` | Primary (broker A) | Detects trades and writes signal files |
| `LoadBalancerSlave`  | Each secondary (B, C, D…) | Reads signal files and executes mirrored trades |

Communication is file-based (a shared folder on the same machine, or a network share).

---

## How it works

```
[Broker A terminal]              [Broker B terminal]
 LoadBalancerMaster               LoadBalancerSlave
       │                                │
  OnTradeTransaction()      ←─ polls ──►│
  or OnTimer()                   every N sec
       │                                │
  writes sig_<id>.json ──────────────► reads sig_<id>.json
  to shared folder                executes mirrored trade
                                  renames to sig_<id>.done
                                  alerts on failure
```

### Periodic mode

Every *N* seconds (default: **5 minutes**) the Master writes a `SYNC_CHECK` signal that
contains a full snapshot of its open positions.  
Each Slave compares the snapshot against its own positions and:

- Opens missing positions (scaled by ratio).
- Closes orphan positions not present on the master.
- Adjusts volume when the difference exceeds one lot step.

### Hook mode

Every time a deal is executed on the master account (`OnTradeTransaction`), the Master
immediately writes a signal file.  
Slaves pick it up on their next poll cycle (configurable, default: **5 seconds**).

Both modes can be active simultaneously (`SYNC_MODE_BOTH`).

---

## Project structure

```
mt5_load_balancer/
├── .github/
│   └── workflows/
│       └── ci.yml                  ← GitHub Actions CI
├── MQL5/
│   ├── Experts/
│   │   └── LoadBalancer/
│   │       ├── LoadBalancerMaster.mq5
│   │       └── LoadBalancerSlave.mq5
│   └── Include/
│       └── LoadBalancer/
│           ├── Config.mqh          ← constants & defaults
│           ├── TradeSignal.mqh     ← signal struct + JSON serialisation
│           ├── PositionSync.mqh    ← volume scaling, file I/O, order execution
│           └── Notifications.mqh  ← Alert / push / email helpers
├── src/
│   └── lb_core.py                 ← Python mirror of MQL5 logic (for unit tests)
├── tests/
│   ├── conftest.py
│   ├── test_trade_signal.py
│   ├── test_position_sync.py
│   └── test_notifications.py
├── signals/                       ← runtime signal files (git-ignored)
├── requirements-dev.txt
├── .gitignore
└── README.md
```

---

## Installation

### Prerequisites

- MetaTrader 5 terminal(s) installed and logged into the respective accounts.
- All terminals running on the same machine, **or** a network share accessible by all.

### Steps

1. **Clone the repository** (or download the zip).

2. **Copy MQL5 files** into your MT5 `MQL5` data folder.  
   On Windows the default path is:
   ```
   %APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\
   ```
   Copy:
   - `MQL5/Experts/LoadBalancer/` → `…\MQL5\Experts\LoadBalancer\`
   - `MQL5/Include/LoadBalancer/` → `…\MQL5\Include\LoadBalancer\`

   > Do this for **every** terminal (master and all slaves).

3. **Create the shared signal directory** (e.g. `C:\LB\signals\`) and make sure all
   terminal processes can read/write it.  
   On a single machine you can use the MT5 *Common* folder:
   ```
   %APPDATA%\MetaQuotes\Terminal\Common\LoadBalancer\signals\
   ```
   This is the default when using `FILE_COMMON` flag in MQL5.

4. **Compile the EAs** inside each MT5 terminal via MetaEditor (F7).

5. **Attach EAs to charts:**
   - On the **primary** terminal: attach `LoadBalancerMaster` to any chart (e.g. EURUSD M1).
   - On each **secondary** terminal: attach `LoadBalancerSlave` to any chart.

---

## Configuration

### LoadBalancerMaster inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SyncMode` | `2` (BOTH) | `0` = periodic only, `1` = hooks only, `2` = both |
| `PeriodicInterval` | `300` | Timer interval in seconds |
| `SignalDirectory` | `LoadBalancer\signals\` | Shared signal folder (relative to MT5 Common folder) |

### LoadBalancerSlave inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SlaveRatio` | `1.0` | Volume multiplier (e.g. `0.7` = 70 % of master) |
| `PollIntervalSec` | `5` | How often to check for new signal files (seconds) |
| `SignalDirectory` | `LoadBalancer\signals\` | Must match the Master's setting |
| `NotifyFlags` | `3` (Alert + Print) | Bitmask: 1=Alert, 2=Print, 4=Push, 8=Email, 15=All |

---

## Sync modes

| Mode | Constant | Description |
|------|----------|-------------|
| Periodic | `SYNC_MODE_PERIODIC = 0` | Timer fires every `PeriodicInterval` seconds |
| Hooks | `SYNC_MODE_HOOKS = 1` | `OnTradeTransaction` fires on every deal |
| Both | `SYNC_MODE_BOTH = 2` | Hooks for low latency + periodic as safety net |

---

## Volume ratio

Set `SlaveRatio` on each slave independently:

| SlaveRatio | Effect |
|------------|--------|
| `1.0` | 100 % mirror — identical volume |
| `0.7` | 70 % of master volume (rounded down to lot step) |
| `0.5` | Half the master volume |
| `2.0` | Double the master volume |

Volume is always clamped to the instrument's `SYMBOL_VOLUME_MIN` / `SYMBOL_VOLUME_MAX` range
and rounded down to `SYMBOL_VOLUME_STEP`.

---

## Failure notifications

When a slave fails to execute a trade (insufficient funds, instrument unavailable, etc.),
it notifies you via the channels selected in `NotifyFlags`:

| Flag | Value | Channel |
|------|-------|---------|
| `NOTIFY_ALERT` | 1 | MT5 pop-up `Alert()` dialog |
| `NOTIFY_PRINT` | 2 | Experts journal log |
| `NOTIFY_PUSH`  | 4 | Mobile push notification |
| `NOTIFY_EMAIL` | 8 | Email (requires MT5 email config) |
| `NOTIFY_ALL`   | 15 | All of the above |

Combine flags with bitwise OR: e.g. `Alert + Email = 1 + 8 = 9`.

---

## Development & testing

The core business logic (volume scaling, signal serialisation, sync diff) is mirrored in
`src/lb_core.py` so it can be tested in a standard Python environment without MetaTrader.

```bash
# Install test dependencies
pip install -r requirements-dev.txt

# Run all tests
python -m pytest tests/ -v

# Run with coverage
pip install pytest-cov
python -m pytest tests/ --cov=src --cov-report=term-missing

# Lint
pip install ruff
ruff check src/ tests/
```

CI runs automatically on every push and pull request via GitHub Actions (see
`.github/workflows/ci.yml`).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
