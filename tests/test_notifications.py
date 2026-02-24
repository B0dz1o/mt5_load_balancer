"""
tests/test_notifications.py – Unit tests for notification message formatting.

Mirrors the behaviour of NotifyFailure() in
MQL5/Include/LoadBalancer/Notifications.mqh.
"""

from lb_core import NOTIFY_ALERT, NOTIFY_ALL, NOTIFY_PRINT, format_failure_message


class TestFormatFailureMessage:
    def test_contains_account_login(self):
        msg = format_failure_message("123456", "BUY", "EURUSD", "Insufficient funds")
        assert "123456" in msg

    def test_contains_action(self):
        msg = format_failure_message("123456", "SELL", "GBPUSD", "Market closed")
        assert "SELL" in msg

    def test_contains_symbol(self):
        msg = format_failure_message("123456", "BUY", "USDJPY", "Error")
        assert "USDJPY" in msg

    def test_contains_error_message(self):
        error = "OrderSend failed: 10019"
        msg = format_failure_message("123456", "BUY", "EURUSD", error)
        assert error in msg

    def test_contains_lb_slave_prefix(self):
        msg = format_failure_message("99999", "CLOSE", "XAUUSD", "No position")
        assert "[LB Slave" in msg

    def test_returns_string(self):
        assert isinstance(format_failure_message("1", "BUY", "A", "E"), str)

    def test_empty_error_message(self):
        msg = format_failure_message("1", "BUY", "EURUSD", "")
        assert "BUY" in msg
        assert "EURUSD" in msg

    def test_special_chars_in_error(self):
        error = "ret=10027 & reason=<invalid>"
        msg = format_failure_message("1", "BUY", "EURUSD", error)
        assert error in msg


class TestNotifyFlags:
    """Verify the bitmask constants behave as expected."""

    def test_alert_flag(self):
        assert NOTIFY_ALERT == 0x01

    def test_print_flag(self):
        assert NOTIFY_PRINT == 0x02

    def test_all_includes_alert(self):
        assert NOTIFY_ALL & NOTIFY_ALERT != 0

    def test_all_includes_print(self):
        assert NOTIFY_ALL & NOTIFY_PRINT != 0

    def test_flags_are_independent_bitmasks(self):
        # Combining two flags should not equal either individually
        combined = NOTIFY_ALERT | NOTIFY_PRINT
        assert combined != NOTIFY_ALERT
        assert combined != NOTIFY_PRINT

    def test_flag_isolation(self):
        flags = NOTIFY_ALERT
        assert (flags & NOTIFY_ALERT) != 0
        assert (flags & NOTIFY_PRINT) == 0
