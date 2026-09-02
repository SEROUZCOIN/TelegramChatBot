"""In-memory snapshot store.

The dashboard has three possible feeds — the EA's HTTP telemetry, a direct
MetaTrader5 terminal connection, and the synthetic demo generator — and all
three write the SAME snapshot shape here. Every figure reads from this store
and nowhere else, so adding a feed never touches the rendering code.

Only the newest snapshot is authoritative; the deques keep the history the
time-series and 3D terrain plots need. Nothing is persisted: restart the
dashboard and it starts from the next snapshot.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from typing import Any, Deque, Dict, List, Optional

HISTORY_MAX = 4000  # ~1 hour at one snapshot per second
EVENTS_MAX = 200


def _empty_snapshot() -> Dict[str, Any]:
    """The shape every consumer can rely on, even before a feed connects."""
    return {
        "ea": "GRID FIBONACCI PRO",
        "version": "-",
        "magic": 0,
        "ts": 0,
        "last_event": "waiting for feed",
        "source": "none",
        "account": {
            "company": "-", "currency": "USD", "login": 0,
            "balance": 0.0, "equity": 0.0, "margin": 0.0,
            "free_margin": 0.0, "margin_level": 0.0, "hedging": True,
        },
        "market": {
            "symbol": "-", "timeframe": "-", "bid": 0.0, "ask": 0.0,
            "spread_points": 0, "digits": 5,
        },
        "spec": {
            "point": 0.00001, "tick_size": 0.00001, "tick_value": 1.0,
            "volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0,
            "max_levels": 6, "cycle_max_loss_pct": 4.0,
            "max_dd_pct": 12.0, "max_daily_loss_pct": 4.0,
        },
        "regime": {
            "regime": "CHOP", "bias": 0, "stack_dir": 0, "htf_dir": 0,
            "ma_fast": 0.0, "ma_mid": 0.0, "ma_slow": 0.0, "ma_htf": 0.0,
            "slope_atr": 0.0, "adx": 0.0, "di_plus": 0.0, "di_minus": 0.0,
            "atr": 0.0,
        },
        "swing": {
            "valid": False, "dir": 0, "high": 0.0, "low": 0.0,
            "range": 0.0, "high_time": 0, "low_time": 0,
        },
        "cycle": {
            "active": False, "dir": 0, "levels": 0, "avg_price": 0.0,
            "volume": 0.0, "floating": 0.0, "realised": 0.0,
            "next_price": 0.0, "stop_price": 0.0,
            "tp1": 0.0, "tp2": 0.0, "tp3": 0.0,
            "tp1_done": False, "tp2_done": False, "be_done": False,
            "started": 0,
        },
        "guard": {
            "trading_enabled": False, "grid_enabled": False, "halted": False,
            "daily_target_hit": False, "halt_reason": "",
            "day_pl": 0.0, "day_start_balance": 0.0,
            "peak_equity": 0.0, "dd_pct": 0.0,
        },
        "stats": {
            "cycles_total": 0, "cycles_won": 0, "realised_total": 0.0,
            "best_cycle": 0.0, "worst_cycle": 0.0, "max_dd_pct": 0.0,
            "trades_sent": 0, "trades_failed": 0,
        },
        "levels": [],
    }


class SnapshotStore:
    """Thread-safe. Feeds write from their own threads, Dash reads from its."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._snapshot: Dict[str, Any] = _empty_snapshot()
        self._received_at: float = 0.0
        self.equity: Deque[float] = deque(maxlen=HISTORY_MAX)
        self.balance: Deque[float] = deque(maxlen=HISTORY_MAX)
        self.floating: Deque[float] = deque(maxlen=HISTORY_MAX)
        self.dd_pct: Deque[float] = deque(maxlen=HISTORY_MAX)
        self.levels_open: Deque[int] = deque(maxlen=HISTORY_MAX)
        self.stamps: Deque[float] = deque(maxlen=HISTORY_MAX)
        self.events: Deque[Dict[str, Any]] = deque(maxlen=EVENTS_MAX)

    # -- writing ----------------------------------------------------------
    def update(self, payload: Dict[str, Any], source: str) -> None:
        """Merge one snapshot in, filling any block the feed left out."""
        merged = _empty_snapshot()
        for key, value in payload.items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                merged[key].update(value)
            else:
                merged[key] = value
        merged["source"] = source

        now = time.time()
        with self._lock:
            previous_event = self._snapshot.get("last_event")
            self._snapshot = merged
            self._received_at = now

            account = merged["account"]
            cycle = merged["cycle"]
            self.stamps.append(now)
            self.equity.append(float(account.get("equity", 0.0)))
            self.balance.append(float(account.get("balance", 0.0)))
            self.floating.append(float(cycle.get("floating", 0.0)))
            self.dd_pct.append(float(merged["guard"].get("dd_pct", 0.0)))
            self.levels_open.append(int(cycle.get("levels", 0)))

            event = merged.get("last_event")
            if event and event != previous_event:
                self.events.appendleft({
                    "time": time.strftime("%H:%M:%S", time.localtime(now)),
                    "text": str(event),
                    "floating": float(cycle.get("floating", 0.0)),
                })

    def note_event(self, text: str) -> None:
        with self._lock:
            self.events.appendleft({
                "time": time.strftime("%H:%M:%S"),
                "text": text,
                "floating": 0.0,
            })

    # -- reading ----------------------------------------------------------
    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return self._snapshot

    def age_seconds(self) -> Optional[float]:
        with self._lock:
            if self._received_at == 0.0:
                return None
            return time.time() - self._received_at

    def series(self) -> Dict[str, List[float]]:
        with self._lock:
            return {
                "stamps": list(self.stamps),
                "equity": list(self.equity),
                "balance": list(self.balance),
                "floating": list(self.floating),
                "dd_pct": list(self.dd_pct),
                "levels": list(self.levels_open),
            }

    def event_list(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self.events)


STORE = SnapshotStore()
