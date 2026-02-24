# agents.md

> "An army of agents, each with a single purpose, together unstoppable."

---

## Philosophy

This project embraces an **agent-based architecture** both in its MQL5 implementation and
in how we think about software development itself.

Each Expert Advisor is an autonomous agent:

| Agent | Responsibility | Trigger |
|-------|---------------|---------|
| **LoadBalancerMaster** | Observe trades on the primary account and broadcast signals | `OnTradeTransaction`, `OnTimer` |
| **LoadBalancerSlave** | Consume signals and replicate trades on a secondary account | `OnTimer` (file poll) |

Agents communicate exclusively through **signal files** — a simple, durable message bus.
No agent knows about the internal state of another; they only read and write shared messages.

---

## Design principles

1. **Single responsibility** – each EA does exactly one job.
2. **Loose coupling** – agents communicate through files, not direct calls.
3. **Fail loudly** – errors are surfaced immediately via alerts, not silently swallowed.
4. **Idempotency** – processing the same signal twice should not create duplicate trades
   (signal files are renamed to `.done` after processing).
5. **Observability** – every important action is logged to the MT5 Experts journal.

---

## Adding a new agent

To add a new behaviour (e.g. a risk-management agent that auto-reduces positions):

1. Create `MQL5/Experts/LoadBalancer/LoadBalancerRiskManager.mq5`.
2. Include the shared headers from `MQL5/Include/LoadBalancer/`.
3. Write or read signal files using `WriteSignalFile` / `ReadSignalFile` from `PositionSync.mqh`.
4. Add a new `ENUM_SIGNAL_ACTION` value in `TradeSignal.mqh` if a new signal type is needed.
5. Update this file and `README.md`.

---

## AI-assisted development

This project was designed with AI coding agents in mind.  
When using an AI assistant to extend the code:

- Always point the AI to `src/lb_core.py` — it is the **single source of truth** for
  the business logic and is fully unit-tested.
- Make changes to `lb_core.py` first, then port them to the corresponding `.mqh` / `.mq5` file.
- Run `python -m pytest tests/ -v` after every change.
