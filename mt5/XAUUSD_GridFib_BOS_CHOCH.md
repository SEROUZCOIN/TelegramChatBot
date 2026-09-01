# XAUUSD GridFib BOS/CHOCH — v3.00

A gold Expert Advisor that decides *direction* from market structure and manages
*exposure* as a capped recovery grid. v3.00 continues the v2.00 source: nothing
was removed, and the features v2.00 declared but never wired up are now live.

> Research software. A grid with lot progression can lose more than any single
> trade ever risks. Run it on a demo account first, and size the ladder so that
> filling every level is survivable.

## How it trades

**1. Direction — market structure.** On each closed bar of the structure
timeframe the EA confirms swing pivots (`InpPivotLeft`/`InpPivotRight` bars on
both sides, so a swing is only confirmed after the fact and never repaints). A
close beyond the last confirmed swing, plus `InpBreakBufferPrice`, is a **BOS**
when it extends the current trend and a **CHOCH** when it reverses it.

**2. Permission — confluence.** A signal alone does not open anything. The entry
price is scored against the context the EA maintains: trend, higher-timeframe
EMA bias, swing support/resistance, order blocks, demand/supply zones,
unmitigated fair value gaps, liquidity sweeps, the Fibonacci zone and DOM
imbalance. The score must reach `ActiveRequiredConfluence()` for the profile, and
the NORMAL profile additionally requires at least one *location* factor (OB, SNR,
SND or FVG) — a trend reading on its own is not a level to trade at. The panel
shows the score and the exact factor list, so a held setup is always explainable.

**3. Entry — now or on the retracement.** With the Fibonacci filter on, the EA
arms a zone between the shallow and deep ratios of the impulse and waits for
price to return into it, expiring after `InpFibEntryExpiryBars`. With it off, the
armed signal fills at market.

**4. Exposure — the grid.** If price moves against the basket by the current
grid distance, the next level opens. Distance comes from ATR with a volatility
regime switch (quiet / normal / volatile multipliers) and widens with depth on
the Fibonacci sequence, so a runaway trend cannot fill the whole ladder at once.
Lot progression is fixed, geometric, Fibonacci or risk-percent — always capped by
`InpMaxLotPerOrder` and `InpMaxBasketLots`.

**5. Exit — the basket, not the trade.** The whole basket closes on a money
target, a money stop, a profit trail (give back `InpTrailGivebackMoney` from the
peak), a time stop, an opposite structure event, or an account risk lock.
Individually, positions get break-even, ATR trailing stops and an optional
partial close.

## What v3.00 adds

| Area | v3.00 |
|---|---|
| Tick microstructure | 256-tick ring buffer, signed micro impulse, tick rate |
| Depth of market | `OnBookEvent` subscription, ladder imbalance in [-1, 1], staleness expiry |
| Smart money | Unmitigated fair value gaps, liquidity sweeps, premium/discount filter |
| Multi-timeframe | HTF EMA bias that scores confluence and can veto counter-trend entries |
| Position management | Break-even, ATR trailing stop, partial close (stops-level and no-op safe) |
| Account protection | Daily profit lock alongside the daily loss and equity drawdown locks |
| News | MQL5 economic calendar filter by currency and importance, with an optional pre-event flatten |
| Reporting | Terminal alerts, push notifications, queued Telegram messages, CSV journal, session statistics |
| Persistence | Binary state file keyed by account+symbol+magic, reconciled against live positions |
| Dashboard | Neon theme library, live profile switching, DOM/impulse row, session stats, heartbeat |
| Tester | `OnTester` criterion: profit × capped profit factor × √trades, divided by drawdown |

Fixed from v2.00: the profile system was never seeded from `InpTradingProfile`,
so every profile input, the DOM/tick inputs and the panel switch were dead; ATR
handles ignored the profile timeframe; basket exits used raw inputs instead of
the profile-scaled targets; `ActiveMaxBasketMinutes()` was never called; the new
bar check used the input timeframe rather than the active one; and the UI colour
tokens were declared but unused.

**One behaviour change to know about:** the NORMAL profile now honours
`InpUseFibRetracement` instead of always waiting for a retracement (in v2.00 the
input was unreachable). With the default `false`, NORMAL fills armed signals at
market. Set it to `true` for the v2.00 behaviour. HFT and AGGRESSIVE never wait;
INSANE always does.

## Profiles

Switch from the panel (`InpAllowDashboardProfileSwitch`) or set the starting one
in the inputs. Switching rebuilds indicator handles and re-reads structure.

| Profile | Structure TF | Max levels | Lots | Target | Character |
|---|---|---|---|---|---|
| NORMAL | Input | ≤5 | Input mode | 100% | Structure trading with strict confluence |
| HFT | M1 | ≤4 | Fixed × 0.75 | 25% | Tick and DOM scalp, 1s throttle, 5-minute time stop |
| AGGRESSIVE | M5 | Input | Geometric × 1.5 | 80% | Wider ladder, faster re-entry |
| INSANE | M1 | ≤2 | Geometric × 3.0 | 400% | Rare setups, 4-factor confluence, deep Fibonacci only |

## Installation

1. Copy `XAUUSD_GridFib_BOS_CHOCH.mq5` to `MQL5/Experts/` and compile it in
   MetaEditor (F7). No external includes beyond the standard `Trade` library.
2. Attach it to an **XAUUSD / GOLD** chart. Any timeframe works — the EA reads
   the timeframes it needs; `InpRequireGoldSymbol` refuses anything else.
3. Enable AutoTrading. On a netting account the EA says so in the log and tracks
   grid depth in its state file rather than per ticket.
4. For Telegram, allow `https://api.telegram.org` in
   *Tools → Options → Expert Advisors → Allow WebRequest for listed URL*, then
   fill in `InpTelegramToken` and `InpTelegramChatId`. Messages are queued and
   sent from the timer, never from the tick path.
5. Push notifications need a MetaQuotes ID in *Tools → Options → Notifications*.

## Input groups

| Group | What to set first |
|---|---|
| Identity and execution | `InpMagic` (one per chart), deviation, long/short permission |
| Runtime trading profiles | Starting profile and the per-profile lot/target/distance factors |
| HFT tick and DOM scalp | Tick window, micro impulse size, DOM threshold, signal gap |
| BOS / CHOCH | Structure timeframe, pivot width, break buffer, accepted events |
| Smart money confluence | FVG, sweeps, premium/discount, HTF timeframe and EMA pair |
| Fibonacci entry | Retracement on/off, shallow/deep ratios, setup expiry |
| Grid and automatic distance | Level cap, distance mode, ATR settings, regime multipliers, min/max distance |
| Lot progression | Mode, base lot, multiplier, **per-order and basket lot caps** |
| Basket exits | Money target/stop, profit trail, time stop, cooldown |
| Per-position protection | Break-even, ATR trailing, partial close |
| Account protection | Daily loss, daily profit lock, equity drawdown, spread, margin, session hours |
| News filter | Importance level, currencies, minutes before/after, optional flatten |
| Alerts and reporting | Terminal alerts, push, Telegram, CSV journal |
| Chart control panel | Show, corner, offsets |

The two caps that actually bound the risk are `InpMaxLotPerOrder` and
`InpMaxBasketLots`; every sizing path is floored to the volume step and clamped
by both. `InpMaxGridLevels` bounds how deep the ladder can go, and the profile
may lower it further.

## Strategy Tester guidance

- Use **Every tick based on real ticks** for gold. Tick-modelled runs will not
  reproduce grid fills or micro-impulse behaviour, and the HFT profile is
  meaningless without real ticks.
- The economic calendar and `WebRequest` are unavailable in the tester, so the
  news filter and Telegram are skipped there by design — a backtest is
  news-blind, and a live run is not. Compare the two accordingly.
- Depth of market is not simulated: the DOM confluence factor is simply never
  scored in a backtest, which makes tester results slightly *more* conservative
  than live for the HFT profile.
- Model at least a year, including a trending stretch. A grid flatters itself in
  range and pays for it in trend; a backtest that never met a trend proves
  nothing.
- Check **maximum equity drawdown** and the deepest grid level reached, not just
  net profit. A curve that only ever ran to level 2 has not tested the recovery
  logic at all.
- Set commission and swap to match the live account. Gold swaps matter for a
  basket held overnight.

## Optimization notes

Optimize in this order, and re-test the whole thing after each stage rather than
stacking every parameter into one pass:

1. **Structure**: `InpPivotLeft`/`InpPivotRight` (2–6), `InpBreakBufferPrice`,
   `InpStructureTF`.
2. **Distance**: `InpATRDistanceMultiplier`, the regime ratios and multipliers,
   `InpMinDistancePrice`/`InpMaxDistancePrice`.
3. **Exits**: `InpBasketTakeProfitMoney`, `InpTrailStartMoney`,
   `InpTrailGivebackMoney`.
4. **Progression last**, and narrowly: `InpMartingaleMultiplier` between 1.1 and
   1.5, never with the lot caps removed.

`OnTester` returns profit × capped profit factor × √trades ÷ (1 + drawdown), so
the optimizer prefers a shallow curve with enough trades to mean something over a
single lucky recovery. Anything with fewer than 10 trades scores zero. Always
walk-forward the top results — a grid EA is unusually good at fitting a window.

## Files it writes

Both live in `MQL5/Files` and are named `GFBC_<account>_<symbol>_<magic>`:

- `.bin` — grid level, last entry, day counters, peak equity. Reconciled against
  live positions on start, so a restart resumes an open ladder instead of
  reopening from level one.
- `.csv` — entries, partial closes, break-even moves, exit deals, basket results
  and a session summary. Written only outside optimization.

## Possible next steps

- Adopt the repo's `SignalBridge` contract so structure events publish to the
  platform as signals rather than only to Telegram.
- Order block *mitigation* tracking (a zone list with per-zone state) instead of
  the single most recent block per side.
- Session-aware distance: Asia/London/New York volatility profiles rather than a
  single ATR regime switch.
- Correlation guard for DXY, and a spread-percentile filter instead of a fixed
  `InpMaxSpreadPrice`.
- Persist session statistics across restarts by rebuilding them from deal history
  rather than from the current run only.
