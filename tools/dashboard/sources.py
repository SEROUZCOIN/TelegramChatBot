"""Feeds that fill the snapshot store.

Three of them, all producing the identical shape:

  TelemetryFeed  the EA POSTs to /ingest  (any OS, including a Linux VPS)
  MT5Feed        this process talks to a local MetaTrader 5 terminal (Windows)
  DemoFeed       a synthetic market, so the dashboard can be seen without MT5

MT5Feed recomputes the SAME structure the EA sees — triple MA stack, ADX,
ATR-normalised slope, confirmed pivots and the Fibonacci geometry — from the
terminal's own bars. It is a second opinion on the EA's view, not a copy of it.
"""

from __future__ import annotations

import random
import threading
import time
from typing import Any, Dict, List, Optional

from store import STORE


# ---------------------------------------------------------------------------
# Small indicator kit — no pandas, no TA library
# ---------------------------------------------------------------------------
def ema(values: List[float], period: int) -> List[float]:
    if not values or period < 1:
        return []
    k = 2.0 / (period + 1.0)
    out = [values[0]]
    for v in values[1:]:
        out.append(v * k + out[-1] * (1 - k))
    return out


def wilder(values: List[float], period: int) -> List[float]:
    """Wilder smoothing — what ATR and ADX actually use."""
    if len(values) < period or period < 1:
        return []
    out = [sum(values[:period]) / period]
    for v in values[period:]:
        out.append((out[-1] * (period - 1) + v) / period)
    return out


def atr_series(high: List[float], low: List[float], close: List[float],
               period: int) -> List[float]:
    trs = []
    for i in range(1, len(close)):
        trs.append(max(high[i] - low[i],
                       abs(high[i] - close[i - 1]),
                       abs(low[i] - close[i - 1])))
    return wilder(trs, period)


def adx_series(high: List[float], low: List[float], close: List[float],
               period: int) -> tuple:
    """Returns (adx, +di, -di), Wilder's original formulation."""
    plus_dm, minus_dm, trs = [], [], []
    for i in range(1, len(close)):
        up = high[i] - high[i - 1]
        down = low[i - 1] - low[i]
        plus_dm.append(up if (up > down and up > 0) else 0.0)
        minus_dm.append(down if (down > up and down > 0) else 0.0)
        trs.append(max(high[i] - low[i],
                       abs(high[i] - close[i - 1]),
                       abs(low[i] - close[i - 1])))

    tr_s = wilder(trs, period)
    plus_s = wilder(plus_dm, period)
    minus_s = wilder(minus_dm, period)
    if not tr_s or not plus_s or not minus_s:
        return [], [], []

    plus_di, minus_di, dx = [], [], []
    for tr, p, m in zip(tr_s, plus_s, minus_s):
        if tr <= 0:
            plus_di.append(0.0)
            minus_di.append(0.0)
            dx.append(0.0)
            continue
        pdi = 100.0 * p / tr
        mdi = 100.0 * m / tr
        plus_di.append(pdi)
        minus_di.append(mdi)
        total = pdi + mdi
        dx.append(100.0 * abs(pdi - mdi) / total if total > 0 else 0.0)

    return wilder(dx, period), plus_di, minus_di


def find_swing(high: List[float], low: List[float], strength: int,
               lookback: int, atr: float, min_atr: float) -> Dict[str, Any]:
    """The EA's leg detection, reimplemented on plain lists.

    Index 0 here is the NEWEST bar, matching the EA's shift convention.
    """
    empty = {"valid": False, "dir": 0, "high": 0.0, "low": 0.0, "range": 0.0,
             "high_time": 0, "low_time": 0}
    n = min(len(high), len(low))
    horizon = min(lookback, n - strength - 2)
    if horizon < strength * 4:
        return empty

    def pivot_high(s: int) -> bool:
        return all(high[s + k] <= high[s] and high[s - k] <= high[s]
                   for k in range(1, strength + 1))

    def pivot_low(s: int) -> bool:
        return all(low[s + k] >= low[s] and low[s - k] >= low[s]
                   for k in range(1, strength + 1))

    pivot_shift, is_high = -1, False
    for s in range(strength + 1, horizon):
        ph, pl = pivot_high(s), pivot_low(s)
        if ph or pl:
            is_high = ph if not (ph and pl) else True
            pivot_shift = s
            break
    if pivot_shift < 0:
        return empty

    origin_shift, origin_price = -1, 0.0
    for s in range(pivot_shift + 1, horizon):
        value = low[s] if is_high else high[s]
        better = (origin_shift < 0
                  or (is_high and value < origin_price)
                  or (not is_high and value > origin_price))
        if better:
            origin_price, origin_shift = value, s
    if origin_shift < 0:
        return empty

    pivot_price = high[pivot_shift] if is_high else low[pivot_shift]
    span = abs(pivot_price - origin_price)
    if span <= 0 or (atr > 0 and span < min_atr * atr):
        return empty

    return {
        "valid": True,
        "dir": 1 if is_high else -1,
        "high": pivot_price if is_high else origin_price,
        "low": origin_price if is_high else pivot_price,
        "range": span,
        "high_time": 0,
        "low_time": 0,
    }


# ---------------------------------------------------------------------------
# MT5 terminal feed
# ---------------------------------------------------------------------------
class MT5Feed(threading.Thread):
    """Polls a local MetaTrader 5 terminal through the official Python API."""

    def __init__(self, symbol: str, magic: int = 0, timeframe: str = "M15",
                 interval: float = 2.0) -> None:
        super().__init__(daemon=True, name="mt5-feed")
        self.symbol = symbol
        self.magic = magic
        self.timeframe = timeframe
        self.interval = interval
        self._stop = threading.Event()
        self._mt5 = None

    def stop(self) -> None:
        self._stop.set()

    def connect(self) -> bool:
        try:
            import MetaTrader5 as mt5  # noqa: N813
        except ImportError:
            STORE.note_event("MetaTrader5 package not installed - MT5 feed disabled")
            return False

        if not mt5.initialize():
            STORE.note_event(f"MT5 initialize() failed: {mt5.last_error()}")
            return False

        self._mt5 = mt5
        if not mt5.symbol_select(self.symbol, True):
            STORE.note_event(f"MT5 could not select {self.symbol}")
            return False

        STORE.note_event(f"MT5 terminal connected - {self.symbol}")
        return True

    def _timeframe_const(self):
        mt5 = self._mt5
        return {
            "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15, "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
            "D1": mt5.TIMEFRAME_D1,
        }.get(self.timeframe.upper(), mt5.TIMEFRAME_M15)

    def run(self) -> None:
        if not self.connect():
            return
        peak_equity = 0.0
        day_start_balance = 0.0
        day_key = None

        while not self._stop.is_set():
            try:
                snap = self.build(peak_equity, day_start_balance, day_key)
                if snap:
                    equity = snap["account"]["equity"]
                    peak_equity = max(peak_equity, equity)
                    today = time.strftime("%Y-%m-%d")
                    if day_key != today:
                        day_key = today
                        day_start_balance = snap["account"]["balance"]
                    snap["guard"]["peak_equity"] = peak_equity
                    snap["guard"]["day_start_balance"] = day_start_balance
                    snap["guard"]["day_pl"] = equity - day_start_balance
                    snap["guard"]["dd_pct"] = (
                        (peak_equity - equity) / peak_equity * 100.0
                        if peak_equity > 0 else 0.0
                    )
                    STORE.update(snap, source="mt5")
            except Exception as exc:  # a feed must never take the UI down
                STORE.note_event(f"MT5 feed error: {exc}")
            self._stop.wait(self.interval)

        if self._mt5 is not None:
            self._mt5.shutdown()

    def build(self, peak_equity: float, day_start_balance: float,
              day_key: Optional[str]) -> Optional[Dict[str, Any]]:
        mt5 = self._mt5
        info = mt5.symbol_info(self.symbol)
        tick = mt5.symbol_info_tick(self.symbol)
        account = mt5.account_info()
        if info is None or tick is None or account is None:
            return None

        rates = mt5.copy_rates_from_pos(self.symbol, self._timeframe_const(), 0, 600)
        if rates is None or len(rates) < 260:
            return None

        close = [float(r["close"]) for r in rates]
        high = [float(r["high"]) for r in rates]
        low = [float(r["low"]) for r in rates]

        fast = ema(close, 21)[-1]
        mid = ema(close, 55)[-1]
        slow_series = ema(close, 200)
        slow = slow_series[-1]
        atr_vals = atr_series(high, low, close, 14)
        atr = atr_vals[-1] if atr_vals else 0.0
        adx_vals, pdi, mdi = adx_series(high, low, close, 14)
        adx = adx_vals[-1] if adx_vals else 0.0

        slope = 0.0
        if atr > 0 and len(slow_series) > 6:
            slope = (slow_series[-1] - slow_series[-6]) / 5.0 / atr

        stack = 1 if fast > mid > slow else (-1 if fast < mid < slow else 0)
        trending = adx >= 22.0 and stack != 0 and abs(slope) >= 0.10
        regime = ("TREND UP" if stack > 0 else "TREND DOWN") if trending else (
            "RANGE" if adx <= 18.0 else "CHOP")

        # newest-first, to match the EA's shift indexing
        swing = find_swing(high[::-1], low[::-1], 3, 180, atr, 2.0)

        positions = mt5.positions_get(symbol=self.symbol) or []
        mine = [p for p in positions if self.magic in (0, p.magic)]
        volume = sum(p.volume for p in mine)
        floating = sum(p.profit + p.swap for p in mine)
        avg = (sum(p.price_open * p.volume for p in mine) / volume) if volume else 0.0
        direction = 0
        if mine:
            dirs = {1 if p.type == mt5.POSITION_TYPE_BUY else -1 for p in mine}
            direction = dirs.pop() if len(dirs) == 1 else 0

        levels = []
        for index, p in enumerate(sorted(mine, key=lambda q: q.time)):
            levels.append({
                "level": index, "ticket": int(p.ticket),
                "requested": float(p.price_open), "filled": float(p.price_open),
                "current": float(p.price_current), "lots": float(p.volume),
                "pl": float(p.profit + p.swap), "opened": int(p.time),
                "closed": False,
            })

        stop = min((p.sl for p in mine if p.sl > 0), default=0.0) if direction > 0 else \
            max((p.sl for p in mine if p.sl > 0), default=0.0)

        return {
            "ea": "MT5 TERMINAL (direct)",
            "version": "-",
            "magic": self.magic,
            "ts": int(time.time()),
            "last_event": f"{len(mine)} position(s) on {self.symbol}",
            "account": {
                "company": account.company, "currency": account.currency,
                "login": int(account.login), "balance": float(account.balance),
                "equity": float(account.equity), "margin": float(account.margin),
                "free_margin": float(account.margin_free),
                "margin_level": float(account.margin_level),
                "hedging": True,
            },
            "market": {
                "symbol": self.symbol, "timeframe": self.timeframe,
                "bid": float(tick.bid), "ask": float(tick.ask),
                "spread_points": int(info.spread), "digits": int(info.digits),
            },
            "spec": {
                "point": float(info.point),
                "tick_size": float(info.trade_tick_size or info.point),
                "tick_value": float(info.trade_tick_value or 1.0),
                "volume_min": float(info.volume_min),
                "volume_step": float(info.volume_step),
                "volume_max": float(info.volume_max),
                "max_levels": 6, "cycle_max_loss_pct": 4.0,
                "max_dd_pct": 12.0, "max_daily_loss_pct": 4.0,
            },
            "regime": {
                "regime": regime, "bias": stack if trending else 0,
                "stack_dir": stack, "htf_dir": 0,
                "ma_fast": fast, "ma_mid": mid, "ma_slow": slow, "ma_htf": 0.0,
                "slope_atr": slope, "adx": adx,
                "di_plus": pdi[-1] if pdi else 0.0,
                "di_minus": mdi[-1] if mdi else 0.0,
                "atr": atr,
            },
            "swing": swing,
            "cycle": {
                "active": bool(mine), "dir": direction, "levels": len(mine),
                "avg_price": avg, "volume": volume, "floating": floating,
                "realised": 0.0, "next_price": 0.0, "stop_price": stop,
                "tp1": 0.0, "tp2": 0.0, "tp3": 0.0,
                "tp1_done": False, "tp2_done": False, "be_done": False,
                "started": int(min((p.time for p in mine), default=0)),
            },
            "guard": {
                "trading_enabled": True, "grid_enabled": True, "halted": False,
                "daily_target_hit": False, "halt_reason": "",
                "day_pl": 0.0, "day_start_balance": day_start_balance,
                "peak_equity": peak_equity, "dd_pct": 0.0,
            },
            "stats": {
                "cycles_total": 0, "cycles_won": 0, "realised_total": 0.0,
                "best_cycle": 0.0, "worst_cycle": 0.0, "max_dd_pct": 0.0,
                "trades_sent": 0, "trades_failed": 0,
            },
            "levels": levels,
        }


# ---------------------------------------------------------------------------
# Demo feed
# ---------------------------------------------------------------------------
class DemoFeed(threading.Thread):
    """A synthetic EURUSD-like market that opens, extends and closes cycles.

    It exists so the dashboard can be evaluated — layout, colours, the 3D
    views — without a terminal, and so the ingest schema has a reference
    implementation to check against.
    """

    def __init__(self, interval: float = 1.0) -> None:
        super().__init__(daemon=True, name="demo-feed")
        self.interval = interval
        self._stop = threading.Event()

        self.price = 1.09500
        self.atr = 0.00120
        self.balance = 10_000.0
        self.peak = 10_000.0
        self.day_start = 10_000.0
        self.levels: List[Dict[str, Any]] = []
        self.direction = 0
        self.cycle_started = 0
        self.realised = 0.0
        self.cycles = 0
        self.wins = 0
        self.total = 0.0
        self.swing = {"valid": False, "dir": 0, "high": 0.0, "low": 0.0,
                      "range": 0.0, "high_time": 0, "low_time": 0}
        self.drift = 0.00002
        self.event = "demo feed started"
        self.idle_ticks = 0

    def stop(self) -> None:
        self._stop.set()

    # -- market ----------------------------------------------------------
    def _step_price(self) -> None:
        if random.random() < 0.01:
            self.drift = random.uniform(-0.00006, 0.00006)
        shock = random.gauss(0, self.atr * 0.18)
        self.price = max(0.5, self.price + self.drift + shock)

    def _refresh_swing(self) -> None:
        span = self.atr * random.uniform(3.0, 7.0)
        if random.random() < 0.5:
            self.swing = {"valid": True, "dir": 1,
                          "high": self.price + span * 0.35,
                          "low": self.price - span * 0.65,
                          "range": span, "high_time": 0, "low_time": 0}
        else:
            self.swing = {"valid": True, "dir": -1,
                          "high": self.price + span * 0.65,
                          "low": self.price - span * 0.35,
                          "range": span, "high_time": 0, "low_time": 0}

    # -- cycle -----------------------------------------------------------
    def _open_cycle(self) -> None:
        self._refresh_swing()
        self.direction = self.swing["dir"]
        self.levels = [{
            "level": 0, "ticket": random.randint(10_000, 99_999),
            "requested": self.price, "filled": self.price,
            "current": self.price, "lots": 0.05, "pl": 0.0,
            "opened": int(time.time()), "closed": False,
        }]
        self.cycle_started = int(time.time())
        self.realised = 0.0
        self.event = f"CYCLE OPEN {'LONG' if self.direction > 0 else 'SHORT'} 0.05"

    def _extend_cycle(self) -> None:
        last = self.levels[-1]
        spacing = self.atr * (1.0, 1.618, 2.618, 4.236, 6.854)[
            min(len(self.levels) - 1, 4)]
        step = last["filled"] - self.direction * spacing
        adverse = (self.price <= step) if self.direction > 0 else (self.price >= step)
        if not adverse:
            return
        self.levels.append({
            "level": len(self.levels), "ticket": random.randint(10_000, 99_999),
            "requested": step, "filled": self.price, "current": self.price,
            "lots": round(last["lots"], 2), "pl": 0.0,
            "opened": int(time.time()), "closed": False,
        })
        self.event = f"GRID L{len(self.levels) - 1} added"

    def _close_cycle(self, floating: float, why: str) -> None:
        self.balance += floating
        self.total += floating
        self.cycles += 1
        if floating > 0:
            self.wins += 1
        self.levels = []
        self.direction = 0
        self.realised = 0.0
        self.event = f"CYCLE CLOSED {floating:+.2f} ({why})"

    def _mpp(self) -> float:
        return 1.0 / 0.00001 * 0.1  # ~10 USD per pip per lot, EURUSD-like

    def run(self) -> None:
        while not self._stop.is_set():
            self._step_price()

            floating = 0.0
            for level in self.levels:
                level["current"] = self.price
                level["pl"] = (self.direction * (self.price - level["filled"])
                               * level["lots"] * self._mpp())
                floating += level["pl"]

            if not self.levels:
                # Open on chance, but never leave the dashboard empty for long:
                # someone evaluating it should see a live basket within seconds.
                self.idle_ticks += 1
                if random.random() < 0.06 or self.idle_ticks > 12:
                    self.idle_ticks = 0
                    self._open_cycle()
            else:
                if len(self.levels) < 6:
                    self._extend_cycle()
                target = 40.0 + 8.0 * len(self.levels)
                if floating >= target:
                    self._close_cycle(floating, "basket target")
                    floating = 0.0
                elif floating <= -self.balance * 0.04:
                    self._close_cycle(floating, "cycle loss ceiling")
                    floating = 0.0

            equity = self.balance + floating
            self.peak = max(self.peak, equity)
            STORE.update(self._snapshot(equity, floating), source="demo")
            self._stop.wait(self.interval)

    def _snapshot(self, equity: float, floating: float) -> Dict[str, Any]:
        swing = self.swing
        rng = swing.get("range", 0.0)
        direction = swing.get("dir", 1) or 1
        if rng > 0:
            tp1 = (swing["low"] + 1.272 * rng) if direction > 0 else (swing["high"] - 1.272 * rng)
            tp2 = (swing["low"] + 1.618 * rng) if direction > 0 else (swing["high"] - 1.618 * rng)
            tp3 = (swing["low"] + 2.618 * rng) if direction > 0 else (swing["high"] - 2.618 * rng)
            stop = (swing["low"] - 0.35 * self.atr) if direction > 0 else (swing["high"] + 0.35 * self.atr)
        else:
            tp1 = tp2 = tp3 = stop = 0.0

        volume = sum(lv["lots"] for lv in self.levels)
        avg = (sum(lv["filled"] * lv["lots"] for lv in self.levels) / volume) if volume else 0.0
        next_price = 0.0
        if self.levels and len(self.levels) < 6:
            spacing = self.atr * (1.0, 1.618, 2.618, 4.236, 6.854)[
                min(len(self.levels) - 1, 4)]
            next_price = self.levels[-1]["filled"] - self.direction * spacing

        adx = 14.0 + 22.0 * abs(self.drift) / 0.00006
        stack = 1 if self.drift > 0.00002 else (-1 if self.drift < -0.00002 else 0)
        regime = ("TREND UP" if stack > 0 else "TREND DOWN") if adx >= 22 and stack else (
            "RANGE" if adx <= 18 else "CHOP")

        return {
            "ea": "GRID FIBONACCI PRO (demo)",
            "version": "1.00",
            "magic": 987654321,
            "ts": int(time.time()),
            "last_event": self.event,
            "account": {
                "company": "Demo Broker", "currency": "USD", "login": 1000001,
                "balance": self.balance, "equity": equity,
                "margin": volume * 1000.0,
                "free_margin": equity - volume * 1000.0,
                "margin_level": (equity / (volume * 1000.0) * 100.0) if volume else 0.0,
                "hedging": True,
            },
            "market": {
                "symbol": "EURUSD", "timeframe": "M15",
                "bid": self.price, "ask": self.price + 0.00008,
                "spread_points": 8, "digits": 5,
            },
            "spec": {
                "point": 0.00001, "tick_size": 0.00001, "tick_value": 0.1,
                "volume_min": 0.01, "volume_step": 0.01, "volume_max": 100.0,
                "max_levels": 6, "cycle_max_loss_pct": 4.0,
                "max_dd_pct": 12.0, "max_daily_loss_pct": 4.0,
            },
            "regime": {
                "regime": regime, "bias": stack if regime.startswith("TREND") else 0,
                "stack_dir": stack, "htf_dir": stack,
                "ma_fast": self.price - self.drift * 400,
                "ma_mid": self.price - self.drift * 900,
                "ma_slow": self.price - self.drift * 2000,
                "ma_htf": self.price - self.drift * 3000,
                "slope_atr": self.drift / self.atr * 30.0,
                "adx": adx,
                "di_plus": 20.0 + (10.0 if stack > 0 else -5.0),
                "di_minus": 20.0 + (10.0 if stack < 0 else -5.0),
                "atr": self.atr,
            },
            "swing": swing,
            "cycle": {
                "active": bool(self.levels), "dir": self.direction,
                "levels": len(self.levels), "avg_price": avg, "volume": volume,
                "floating": floating, "realised": self.realised,
                "next_price": next_price, "stop_price": stop,
                "tp1": tp1, "tp2": tp2, "tp3": tp3,
                "tp1_done": False, "tp2_done": False, "be_done": False,
                "started": self.cycle_started,
            },
            "guard": {
                "trading_enabled": True, "grid_enabled": True, "halted": False,
                "daily_target_hit": False, "halt_reason": "",
                "day_pl": equity - self.day_start,
                "day_start_balance": self.day_start,
                "peak_equity": self.peak,
                "dd_pct": (self.peak - equity) / self.peak * 100.0 if self.peak else 0.0,
            },
            "stats": {
                "cycles_total": self.cycles, "cycles_won": self.wins,
                "realised_total": self.total,
                "best_cycle": 0.0, "worst_cycle": 0.0,
                "max_dd_pct": 0.0, "trades_sent": self.cycles,
                "trades_failed": 0,
            },
            "levels": list(self.levels),
        }
