# soul.md

> "What you do with your money is a reflection of what you value."

---

## Why this project exists

Trading across multiple brokers is a fact of life for serious retail traders:

- Brokers fail, get acquired, or become unavailable.
- Spreads differ; some instruments are cheaper on certain platforms.
- Regulatory environments vary; diversification across jurisdictions reduces risk.
- Execution quality is not equal; keeping secondary accounts in sync as a fallback
  means you always have options.

`mt5_load_balancer` is the **connective tissue** between those accounts.

---

## Core values

### Transparency
Every action the EA takes is logged. You can always reconstruct what happened, when,
and why. The signal files in the shared folder are plain JSON — human-readable, not
a black box.

### Autonomy
Your secondary accounts should require zero manual intervention during normal operation.
The tool should be set-and-forget, with notifications only when something genuinely
needs your attention.

### Proportionality
The ratio system reflects the real world: not every account has the same capital.
Scaling positions proportionally respects the risk profile of each account.

### Resilience
A failure on a secondary account should never affect the primary.  
The primary account is the source of truth; everything else adapts to it.

---

## What this project is not

- It is **not** a copy-trading service for third parties.
- It is **not** a signal provider or automated strategy.
- It is **not** a replacement for a proper risk management plan.

It is a tool. Like any tool, it amplifies the skill (and the mistakes) of the person
using it. Use it wisely.

---

## Inspiration

> "Simplicity is the ultimate sophistication." — Leonardo da Vinci

The signal file bus is deliberately simple: write a JSON file, read it, rename it.  
No databases, no message queues, no daemons.  
Simple enough to audit, simple enough to trust.
