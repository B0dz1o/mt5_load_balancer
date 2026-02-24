# Contributing to mt5_load_balancer

Thank you for your interest in improving this project!

---

## Getting started

1. **Fork** the repository and create a feature branch:
   ```bash
   git checkout -b feature/my-improvement
   ```

2. **Install development dependencies:**
   ```bash
   pip install -r requirements-dev.txt
   pip install ruff pytest-cov
   ```

3. **Make your changes** — see the guidelines below.

4. **Run the tests and linter** before opening a PR:
   ```bash
   ruff check src/ tests/
   python -m pytest tests/ -v
   ```

5. Open a **pull request** against `main`.

---

## Code guidelines

### MQL5 (`.mq5` / `.mqh`)

- Follow the existing include structure: shared logic lives in `MQL5/Include/LoadBalancer/`.
- Every public function must have a header comment block.
- Use `LogInfo`, `LogWarning`, `LogError` (from `Notifications.mqh`) — never raw `Print`.
- New signal action types go in `ENUM_SIGNAL_ACTION` in `TradeSignal.mqh`.
- The slave EA must never block the MT5 event loop; keep `OnTimer` fast.

### Python (`src/`, `tests/`)

- `src/lb_core.py` is the canonical source for business logic; port MQL5 changes here.
- All new functions in `src/lb_core.py` must have a corresponding test in `tests/`.
- Follow [PEP 8](https://peps.python.org/pep-0008/); `ruff` enforces it automatically.
- Use `pytest.approx` for floating-point comparisons in tests.

---

## What makes a good PR

- **Small and focused** — one concern per PR.
- **Tests included** — new Python logic must have unit tests.
- **Docs updated** — if you add an input parameter, update `README.md`.
- **CI green** — all GitHub Actions checks must pass.

---

## Reporting bugs

Please open a GitHub issue with:

- MT5 terminal version and build number.
- EA version (visible in the journal on startup).
- The relevant lines from the MT5 Experts log.
- Steps to reproduce.

---

## License

By contributing you agree that your changes will be licensed under the same
[MIT License](LICENSE) as the rest of the project.
