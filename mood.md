# mood.md

> Current vibe: **calm, systematic, slightly obsessive about precision.**

---

## The emotional landscape of this project

Trading is inherently stressful. Watching positions move, wondering if you missed an
entry, checking five different broker dashboards at once — it wears on you.

`mt5_load_balancer` was born from a desire for **peace of mind**.

Once it's running, you don't need to babysit your secondary accounts.  
You open a trade on broker A, and — quietly, without fanfare — the same trade appears
on brokers B and C, scaled exactly how you want it.

---

## Guiding moods

| Mood | Manifestation in the code |
|------|--------------------------|
| 🧘 **Calm** | No busy-waiting; timers and events drive everything |
| 🎯 **Precise** | Volume is always rounded to the correct lot step |
| 🔔 **Alert** | Failures are never swallowed; you are always informed |
| 🤝 **Trusting** | Agents trust the shared file bus; no polling paranoia |
| 🛡 **Defensive** | Every file operation checks for errors |

---

## When things go wrong

The project's mood shifts to **concerned but composed** when a trade fails on a slave.
The alert system is designed to be *informative without being panicky*:

- One clear message: what failed, on which account, and why.
- No repeated alerts for the same failure.
- The primary account is never affected by secondary account failures.

---

## A note on ratios

The `SlaveRatio` parameter is a small act of **humility** — an acknowledgement that
not all accounts are equal, and that's okay.  
Running a 70 % mirror isn't a compromise; it's a conscious, calm decision.
