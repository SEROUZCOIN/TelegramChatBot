# APEX QUANTUM — MT5 Confluence System

A single MQL5 engine built from four classic studies, rewritten in native MQL5 and made
to agree with each other, plus an animated clickable dashboard and an Expert Advisor
that trades its output.

| Source study | What it became |
|---|---|
| Shved Supply and Demand v1.2 | `AQ_Zones.mqh` — graded supply/demand zones |
| Perfect Trend Line (mladen) | `AQ_Structure.mqh` — dual trend rails |
| SHI Channel true | `AQ_Channel.mqh` — premium/discount rails |
| ZigZag on Parabolic (EarnForex) | `AQ_Structure.mqh` — swings, BOS/CHoCH, Fibonacci |

Added on top: fair value gaps, two-timeframe confirmation, a confluence score, fixed
(non-repainting) entry arrows, an animated dashboard with clickable module toggles and a
timeframe switcher, and a full execution layer in the EA.

Everything is timeframe-agnostic — every window is derived from the chart period, so the
same settings behave sensibly from M1 to MN1.

---

## 1. Files and installation

```
MQL5/Indicators/ApexQuantum/      <- copy this folder
    AQ_Apex.mq5                   (compile this)
    AQ_Theme.mqh                  THEME colours + METRICS dimensions
    AQ_Core.mqh                   enums, structs, object factories
    AQ_Zones.mqh                  supply/demand engine
    AQ_Structure.mqh              trend rails, SAR zigzag, BOS/CHoCH, FVG
    AQ_Channel.mqh                parallel channel
    AQ_Signal.mqh                 confluence scoring + entry model
    AQ_Dashboard.mqh              animated clickable panel

MQL5/Experts/ApexQuantum/         <- copy this folder
    AQ_ApexEA.mq5                 (compile this)
```

1. Copy both folders into your terminal's data folder (File → Open Data Folder → MQL5).
2. In MetaEditor compile `AQ_Apex.mq5` first, then `AQ_ApexEA.mq5`.
3. Drag `AQ_Apex` onto a chart. The EA loads the indicator itself through `iCustom`,
   so it does **not** need to be on the chart to trade.
4. Optional (Telegram, EA only): Tools → Options → Expert Advisors → allow
   `https://api.telegram.org`.

Each program is a self-contained folder using quoted relative includes, so you can move
or rename the folder and it still compiles.

---

## 2. Trading logic

### 2.1 Supply and demand zones
Every minor fractal is a candidate level. Its box is built from the fractal's extreme and
the candle close, thickened by `ATR/2 × InpZoneFuzz`. The level is then walked forward
bar by bar to the present:

* a swing that lands inside the box, at least 10 bars after the previous one, is a **retest**;
* a close beyond the box is a **break** — the first break flips the level to the other side
  (support becomes resistance), the second kills it;
* survivors are merged where they overlap, so one price area yields one zone.

Grades, weakest to strongest: `WEAK` (minor fractal, never tested) → `FLIPPED` (changed
side) → `FRESH` (major fractal, untested) → `TESTED` (1–3 retests) → `PROVEN` (4+).
Grade drives both the colour and the weight the zone carries in the score.

### 2.2 Trend rails
Two rails trail the extreme of their window — the fast one over `InpFastLen` bars, the
slow one over `InpSlowLen`. Each rail tracks the window low while price holds above it and
the window high while price holds below. Trend flips only when price closes through
**both** rails, which is what keeps the primary bias from whipsawing.

### 2.3 Market structure
Swings come from Parabolic SAR flips. Each pivot stores the bar where it became *known*,
not just the bar of the extreme — so a break of that swing is only ever evaluated from the
bar the swing was confirmed on. A close through a confirmed swing is a **BOS** when it
continues the current direction and a **CHoCH** when it reverses it.

### 2.4 Imbalance and channel
Fair value gaps are the standard three-bar imbalance, tracked forward in the same pass and
marked mitigated when price fills them. The channel takes the two most recent same-side
fractals as the base rail and slides a parallel rail to the furthest opposite excursion;
price's 0–1 position between the rails is the premium/discount reading.

### 2.5 The confluence score
Each module votes; the sum is clamped to −100…+100 (positive = bullish):

| Vote | Weight |
|---|---|
| Primary trend rail | ±25 |
| Price vs fast rail | ±8 |
| Structure (last BOS/CHoCH) | ±12 |
| Discount / premium inside the live leg | ±8 |
| Supply/demand zone at price | ±6 … ±18 by grade |
| Unfilled fair value gap at price | ±6 |
| Higher timeframe 1 / 2 | ±10 each |
| Channel tilt / position | ±5 each |

### 2.6 Entry arrows
A score alone never draws an arrow. It must also:

1. reach `InpMinScore`;
2. agree with the primary trend rail (the engine never fades it);
3. coincide with a trigger — a pullback into a zone or the fast rail (`PULLBACK`), a trend
   flip (`FLIP`), or either (`BOTH`);
4. close a candle in the signal direction (`InpConfirmCandle`);
5. respect the cooldown, which is tripled before repeating the same direction.

**Repaint policy.** Arrows are evaluated on closed bars only, once, from data already known
at that bar, and are never rewritten afterwards. The two deliberate exceptions, both normal
for their type: the zigzag's *current* leg extends with price until its pivot confirms, and
zone boxes are rebuilt each bar as new retests and breaks arrive. The channel votes only on
the live score, never on history, because a channel is a present-time construct and using
today's channel to score a bar from last month would be look-ahead.

---

## 3. Dashboard

Top-left by default (`InpPanelCorner` moves it). Header shows a pulsing status dot whose
colour follows the bias and whose rhythm doubles while a signal is live, plus a gold sweep
along the header base. The score gauge fills from the centre and eases toward the live
value rather than jumping.

Rows: bias + score, higher timeframe agreement, structure (rail / last break / channel),
nearest demand, nearest supply, ATR + spread + session + zone count, last signal.

Buttons — all clickable, all live:

* `ZONES` `TREND` `CHAN` `SWING` `FVG` `ARROWS` `ALERT` — toggle each module on the chart.
* `RESCAN` — rebuild every engine from scratch on the next calculation.
* `M5 M15 M30 H1 H4 D1` — switch the chart timeframe.
* `-` / `+` in the header collapses and expands the panel.

The inputs only *seed* these switches. Once running, the buttons own the state, so a module
that starts switched off can still be switched on from the panel.

---

## 4. Inputs

### Indicator — ENGINE CORE (this block is the EA's `iCustom` contract; order is fixed)

| Input | Default | Meaning |
|---|---|---|
| `InpLookback` | 600 | Bars analysed by every engine |
| `InpFractalFast` / `InpFractalSlow` | 3.0 / 6.0 | Minor / major fractal width factors |
| `InpZoneFuzz` | 0.75 | Zone thickness in ATR halves |
| `InpZoneMerge` / `InpZoneExtend` | true / true | Merge overlaps / pad by the fuzz distance |
| `InpFastLen` / `InpSlowLen` | 3 / 7 | Trend rail windows |
| `InpSarStep` / `InpSarMax` | 0.02 / 0.20 | Swing engine sensitivity |
| `InpAtrPeriod` | 14 | ATR period (zone thickness, arrow offset, EA stops) |
| `InpUseMtf` | true | Higher timeframe confirmation |
| `InpMtf1` / `InpMtf2` | CURRENT | `PERIOD_CURRENT` = pick 1 and 2 rungs up automatically |
| `InpSigMode` | BOTH | Pullback / Flip / Both |
| `InpMinScore` | 55 | Score needed to arm a signal |
| `InpCooldownBars` | 3 | Bars between signals (×3 for a repeat in the same direction) |
| `InpConfirmCandle` | true | Require a closing candle in the signal direction |

Remaining groups (`ZONES`, `STRUCTURE & OVERLAYS`, `SIGNALS & ALERTS`, `DASHBOARD`) are
presentation and alerting only and are not part of the contract.

### Expert Advisor

The ENGINE block must mirror the indicator's. Beyond it:

* **Symbols & identity** — `InpSymbols` (comma separated; empty = chart symbol), magic,
  comment, slippage.
* **Money & risk** — fixed lot or risk percent; stop from ATR, from the signal zone
  (with an ATR buffer behind it) or fixed points; target as R multiple, ATR, opposite zone,
  fixed points, or none.
* **Trade management** — break even, partial close, ATR trailing, close on opposite signal.
  R is measured against the stop distance as first seen, so moving to break even cannot
  inflate it.
* **Filters & guards** — max spread, max trades total and per symbol, daily loss and daily
  profit limits (percent of the day's starting balance, reset each server day), session
  window, weekday mask, and a manual news blackout list (`"13:25-13:45;15:55-16:20"`).
* **Notifications** — alerts, push, Telegram, verbose journal logging.

> Telegram lives in the EA, not the indicator: `WebRequest` cannot be called from an
> indicator, and it is disabled entirely in the Strategy Tester.

---

## 5. Strategy Tester guidance

* Model: **1 minute OHLC** for routine work; **Every tick based on real ticks** before
  trusting anything with trailing or partial closes, since those are tick-sensitive.
  Do **not** use *Open prices only* — the management layer needs intrabar prices.
* Give the engine warm-up: the first `InpLookback` bars produce no signals, so start the
  test at least that many bars after your data begins.
* Test on the timeframe you intend to trade. The EA takes signals from `InpTf`
  (`PERIOD_CURRENT` = the chart it runs on).
* For multi-symbol runs, add every symbol to Market Watch first, and expect the tester to
  build their history on the first pass.
* `OnTester` returns `profit × profit factor ÷ relative drawdown`, and returns 0 below 30
  trades so thin samples cannot win an optimisation. Select **Custom max** to use it.

## 6. Optimisation recommendations

Optimise in this order, a few parameters at a time — the engine has enough dimensions to
overfit spectacularly if you turn it loose on all of them:

1. `InpMinScore` 45 → 75 step 5. This is the single biggest lever: it trades frequency
   against quality.
2. `InpSigMode` across its three values, then `InpCooldownBars` 2 → 8.
3. `InpFractalFast` 2 → 5 step 0.5 and `InpFractalSlow` 4 → 10 step 1 — these set what
   counts as a swing worth a zone, and matter most on fast timeframes.
4. `InpZoneFuzz` 0.5 → 1.25 step 0.25 (zone thickness against instrument volatility).
5. Only then the EA's `InpSlAtr`, `InpTpRR`, `InpTrailAtr`.

Leave `InpFastLen`/`InpSlowLen` near 3/7 unless the instrument is unusually noisy; they
define the primary bias that everything else is measured against. Walk forward the result
(optimise in-sample, verify on a later untouched window) before running anything live.

## 7. Performance notes

The expensive work — zones, swings, imbalance, channel, higher timeframe rails — runs once
per new bar, not per tick. Per tick the engine only extends ATR and the trend rails and
refreshes the panel. The animation touches four objects per frame at `InpFrameMs`
(90 ms default); raise it or set `InpAnimate=false` on a slow VPS. Zone drawing is capped
by `InpZoneMax`, imbalance boxes by `InpMaxFvg`, structural markers by `InpMaxBreaks`.

## 8. Known limits and next steps

Ideas worth building next, roughly in order of value:

1. **Order blocks and liquidity sweeps** as first-class modules with their own votes —
   the scoring engine already takes them as inputs.
2. **Session ranges** (Asia/London/NY highs and lows) as liquidity targets.
3. **Volume-weighted zone grading** — a retest on heavy volume should outrank a quiet one.
4. **Adaptive scoring** — auto-tune vote weights per instrument from recent outcomes.
5. **A signal journal** written to CSV so score composition can be analysed after the fact.
6. **Pending-order entries** at the zone edge instead of market entries on the close.
7. **Correlation guard** for multi-symbol runs, to stop five correlated longs at once.

Current limits to be aware of: the zigzag's live leg extends until its pivot confirms; a
zone set is rebuilt each bar, so historical arrow context uses zones that existed at the
time but does not re-check whether they broke later; and Telegram/`WebRequest` is
unavailable in the tester and in indicators.

---

*Verify on a demo account before risking capital. Backtest results are not a prediction.*
