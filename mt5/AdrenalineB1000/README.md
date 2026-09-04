# Adrenaline B1000 — MT5 Indicator

**Author: Serro Deriv**

Gann Fan + Auto Trendlines + Fibonacci OTE Block Zone + Gann Square of 9 + Classic Pivots,
with confluence-scored Buy/Sell arrows, an ADRENALINE trend banner and a multi-timeframe dashboard.

Single file, zero dependencies: `AdrenalineB1000.mq5`.

The signature behaviour: **the Fibonacci layer stays completely invisible until price actually
reaches it.** The chart is clean while price is away, then a 40% translucent Buy/Sell block appears
with Fibonacci-based SL and TP the moment price arrives.

A companion martingale EA that trades these levels ships alongside it —
see **[README-EA.md](README-EA.md)** for `AdrenalineB1000EA.mq5`.

---

## 1. Installation

1. Copy `AdrenalineB1000.mq5` into `MQL5\Indicators\AdrenalineB1000\` inside your terminal data
   folder (MetaTrader 5 → **File → Open Data Folder**).
2. Open it in MetaEditor and press **F7** (Compile). Expect `0 errors, 0 warnings`.
3. In MT5, refresh the Navigator (right-click → Refresh), then drag **AdrenalineB1000** onto a chart.
4. Recommended chart timeframes: **M1, M5, M15, M30, H1**. The dashboard always reports
   M1 / M5 / M15 / M30 / H1 / H4 regardless of the chart's own timeframe.

No DLLs, no external indicators, no `MQL5\Include` files are required.

---

## 2. Trading logic

### 2.1 Structure — the impulse leg
A swing high is confirmed only when a bar's high is the highest within `±InpSwingN` bars, so every
swing is confirmed `InpSwingN` bars **after** it printed. Two alternating swings form the active
**impulse leg** A→B:

* Swing low → swing high = **up leg** (bullish bias, look for buys on the pullback)
* Swing high → swing low = **down leg** (bearish bias, look for sells on the pullback)

The leg is invalidated (and all levels are removed) when a **closed** bar breaks the 1.000 level,
i.e. price closes beyond the leg's origin.

### 2.2 Fibonacci
Retracements are measured from B back toward A: `price = B − r × (B − A)` for an up leg.

| Level | Meaning |
|---|---|
| 0.236 / 0.382 | shallow pullbacks |
| **0.500** | Equilibrium — the Premium / Discount split |
| **0.618 – 0.650** | Golden Pocket (highlighted box) |
| **0.705** | OTE sweet spot (dash-dot line) |
| **0.618 – 0.786** | Golden Zone / Optimal Trade Entry (filled box) |
| 0.886 | deep retracement, last defence |
| 1.272 / 1.414 / 1.618 / 2.000 / 2.618 | extension targets, projected from A |

The Golden Zone bounds are configurable (`InpGZ_Start` / `InpGZ_End`). Standard Fibonacci traders
use the narrow 0.618–0.65 pocket; the ICT/SMC framework uses the wider 0.618–0.786 OTE band with
0.705 as the midpoint — both are drawn.

### 2.3 Gann fan
The fan is anchored at the leg's origin pivot (A). The **price unit** is derived dynamically:

```
unit = |B − A| / (barsB − barsA)        // price movement per bar over the impulse
```

Each fan line at bar `d` bars from the pivot is `A ± unit × ratio × d`, with ratios
`1x8 (0.125), 1x4 (0.25), 1x3, 1x2 (0.5), 1x1 (1.0), 2x1, 3x1, 4x1, 8x1`.
The **1x1** line (45° in Gann's own scaling) is the main support/resistance line and is drawn
thicker. Because the unit is derived from the actual leg, the fan is scale-independent and works
identically on EURUSD, XAUUSD, indices and crypto.

`InpGannFilterRatio` selects which fan line the signal engine uses as its trend filter
(default **1x2** — price above it keeps a bullish leg intact).

### 2.4 Gann Square of 9
Levels are derived from the square-root relationship
`level = (√(anchor × scale) ± step × degrees/180)² / scale`.
The price is auto-scaled into the 10 000–100 000 band so the same formula gives sensible step sizes
on a 1.09 FX pair and on a 3 300 gold quote alike. Set `InpSq9Scale` manually to override.

### 2.5 Auto trendlines
The last two confirmed swing highs form the resistance line; the last two confirmed swing lows form
the support line. Both extend to the right and feed the signal engine.

### 2.6 Signal engine — confluence score (max 8)

A signal requires the price to trade **into the Golden Zone in the direction of the impulse leg**.
That mandatory condition is worth 2 points; each additional filter adds 1:

| # | Condition | Points |
|---|---|---|
| 1 | Bar overlaps the Golden Zone and closes inside the leg (mandatory) | 2 |
| 2 | Candle confirmation — directional body close or ≥40% rejection wick | 1 |
| 3 | EMA(21) vs EMA(50) agrees with the leg direction | 1 |
| 4 | Price on the correct side of the selected Gann fan line | 1 |
| 5 | Price on the correct side of the auto trendline | 1 |
| 6 | RSI not stretched (below `InpRsiBuyMax` for buys, above `InpRsiSellMin` for sells) | 1 |
| 7 | Higher-timeframe EMA trend agrees (default H1) | 1 |

An arrow prints when `score ≥ InpMinScore` (default 5/8). Additional guards: minimum impulse size
in ATR, max signals per leg, minimum bars between signals.

### 2.6a Non-repainting — what is guaranteed, and what is not

An arrow, once printed, stays exactly where it printed. Four things enforce that:

1. **Closed bars only.** Signals are written to `rates_total − 2` and older. The forming bar is
   cleared every tick and never receives an arrow.
2. **Swings need both sides.** A swing at bar `c` is confirmed only when bar `c + InpSwingN` closes,
   using a window of bars that are all closed. A swing is therefore never revised.
3. **Write-forward only.** The calculation loop writes `buffer[i]` while processing bar `i` and never
   goes back to an earlier index. There is no path that rewrites a printed arrow.
4. **The MTF filter reads a *closed* higher-timeframe bar.** This is the one that actually bites.
   `iBarShift` returns the H1 bar *containing* the signal bar — which was still forming when the M5
   bar closed, so its EMA value at that instant differs from its final value. Reading it directly
   makes a 5/8 signal score 6/8 after a reload, and the arrow appears or vanishes. The indicator
   therefore steps back one bar and reads the last H1 bar that was definitely closed at that moment.
   The filter is marginally staler; in exchange the score is reproducible.

Two honest caveats:

* The **levels move** when a new swing confirms — new leg, new Fibonacci, new fan. That is what any
  auto-Fibonacci or Gann tool does; it is not the arrows repainting. Arrows already printed do not
  move when the leg changes.
* `InpMaxBars` bounds the replay. On a reload the state machine restarts at
  `rates_total − InpMaxBars`, so the handful of bars at the very start of that window can differ
  from a run with more history behind them. Everything past the first two confirmed swings is
  identical. Set `InpMaxBars = 0` if you need the full history replayed identically.

### 2.6b Signal visuals

**Nothing Fibonacci-related is drawn until price reaches the zone.** With `InpRevealOnTouch` on
(default), the whole Fibonacci layer — retracements, extensions, the OTE block, the pocket, the A/B
markers and the trade plan — is absent from the chart while price is away from the zone. The Gann
fan, the auto trendlines, Square of 9 and the pivots stay visible throughout, so you still have
structure to read; the moment price actually reaches the 0.618 edge the whole Fibonacci layer
appears at once. The touch is checked **every tick**, not once per bar, so an intrabar touch counts,
and it resets with each new impulse leg. Set the input to `false` to have everything always drawn.

**The 40% Block.** Once revealed, the OTE band (0.618 → 0.786) is filled as a **Buy Block** (green
on an up leg) or **Sell Block** (red on a down leg), rendered at `InpBlockOpacity` percent — 40% by
default. MT5 chart objects have no alpha channel, so the block colour is blended with the live chart
background at that percentage, which gives a genuinely translucent look on any chart theme. The
Golden Pocket (0.618–0.650) sits inside it, blended 15 points more opaque so it reads as the core.

**Fibonacci SL and TP.** With the block comes the trade plan for the last signal:

| Element | Level |
|---|---|
| Entry line, solid neon | the signal bar's close |
| `SL` line, dashed red | `InpPlanSlFib` retracement — default 1.000, the leg origin |
| `TP1` line, pulsing green | `InpPlanTp1Fib` extension — default 1.272 |
| `TP2` line, dotted green | `InpPlanTp2Fib` extension — default 1.618 |
| `R:R 1 : x.xx` | computed from entry, SL and TP1 |

TP1 pulses in colour and width and the SL width breathes, driven by one timer at `InpAnimMs`
(default 120 ms). `InpAnimate = false` freezes the animation without removing anything.

**"GANN BUY" approach arrow.** Before price touches the Gann fan filter line or the auto trendline,
an arrow appears just past that level with the text `GANN BUY` / `GANN SELL` (or `TREND BUY` /
`TREND SELL` when the trendline is nearer), plus a dotted line marking the level being approached.
It arms when price is within `InpApproachAtr` × ATR of the level **and on the correct side of it**
for the active leg, and clears itself once price moves away. Since the Fibonacci layer is hidden
until the touch, this arrow is your pre-touch cue.

**ADRENALINE trend banner.** When the impulse leg flips direction, a banner appears in the
**bottom-right corner** of the chart (`InpAdrenalineCorner`, so it can be moved): **ADRENALINE ON**
in neon green when the trend turns up, **ADRENALINE OFF** in red when it turns down. It flashes strongly for `InpAdrenalineFlashSec` seconds after the flip, then
settles into a steady display of the current state. The flip is also printed to the Experts log.

### 2.7 EA integration — exported buffers

`InpEaMode` is deliberately the **first** input. An EA that loads the indicator through `iCustom`
passes `true` for it and nothing else, which suppresses every chart object, the dashboard, its
extra timeframe handles and the timer — without it, the EA's hidden copy fights the visible copy
over identically named objects on the same chart.


| Buffer | Contents | Read at |
|---|---|---|
| 0 | Buy arrow price | signal bar |
| 1 | Sell arrow price | signal bar |
| 2 | Signal: `+1` buy, `-1` sell, `0` none | shift 1 (last closed bar) |
| 3 | Confluence score, 0–8 | shift 1 |
| 4 | Leg direction: `+1` up leg, `-1` down leg, `0` none | shift 0 |
| 5 | Golden Zone upper price (`0` = none) | shift 0 |
| 6 | Golden Zone lower price (`0` = none) | shift 0 |
| 7 | Leg origin = the 1.000 invalidation level (`0` = none) | shift 0 |

```mql5
int h = iCustom(_Symbol, PERIOD_CURRENT, "AdrenalineB1000\\AdrenalineB1000");  // defaults
double sig[1], zoneHi[1];
CopyBuffer(h, 2, 1, 1, sig);      // signal on the last closed bar
CopyBuffer(h, 5, 0, 1, zoneHi);   // live Golden Zone upper bound
```

Buffers 4–7 exist so an EA never has to re-derive the swing/leg/zone logic — the
bundled `AdrenalineB1000EA.mq5` reads exactly these.

---

## 3. Input reference

### 0. Run mode
| Input | Default | Description |
|---|---|---|
| `InpEaMode` | false | Headless mode for `iCustom`: buffers only, no drawings or dashboard. Leave `false` on a chart. Must stay the first input — `iCustom` parameters are positional. |

### 1. Structure / swing engine
| Input | Default | Description |
|---|---|---|
| `InpSwingN` | 5 | Bars on each side required to confirm a swing. Lower = more, earlier swings. |
| `InpMaxBars` | 3000 | Bars to calculate. 0 = whole history (slower on M1). |
| `InpExtendBars` | 30 | How far levels project to the right. |

### 2. Fibonacci
| Input | Default | Description |
|---|---|---|
| `InpShowFib` | true | Draw retracement levels. |
| `InpShowFibExt` | true | Draw 1.272–2.618 targets. |
| `InpGZ_Start` / `InpGZ_End` | 0.618 / 0.786 | Golden Zone bounds. Use 0.618 / 0.650 for the strict pocket. |
| `InpShowGoldenPocket` | true | Highlight 0.618–0.650 inside the block. |
| `InpShowOTE` | true | Draw the 0.705 line. |
| `InpShowEquilibrium` | true | Draw the 0.500 Premium/Discount split. |

### 3. Gann fan
| Input | Default | Description |
|---|---|---|
| `InpShowGann` | true | Draw the fan. |
| `InpGannAutoUnit` | true | Derive the price unit from the leg. |
| `InpGannManualUnit` | 0.0 | Fixed price unit per bar (used when auto is off). |
| `InpGannFilterRatio` | 1x2 | Fan line used as the signal trend filter. |

### 4. Gann Square of 9
| Input | Default | Description |
|---|---|---|
| `InpShowSq9` | true | Draw Square of 9 levels. |
| `InpSq9Anchor` | Leg end | Anchor price: leg end / leg origin / current price. |
| `InpSq9Steps` | 4 | Levels above and below the anchor. |
| `InpSq9Degrees` | 45 | Degrees per step (45 / 90 / 120 / 180). |
| `InpSq9Scale` | 0 | Price scale, 0 = auto. |

### 5–6. Trendlines and pivots
| Input | Default | Description |
|---|---|---|
| `InpShowTrendlines` | true | Auto support/resistance from the last two swings. |
| `InpTL_Ray` | true | Extend trendlines to the right. |
| `InpShowPivots` | false | Classic daily PP / R1–R3 / S1–S3. |

### 7. Signal engine
| Input | Default | Description |
|---|---|---|
| `InpShowArrows` | true | Draw Buy/Sell arrows. |
| `InpMinScore` | 5 | Minimum confluence score out of 8. |
| `InpMaxSignalsPerLeg` | 1 | Prevents clusters inside one pullback. |
| `InpMinBarsBetween` | 5 | Cool-down between signals. |
| `InpEmaFast` / `InpEmaSlow` | 21 / 50 | Trend filter. |
| `InpRsiPeriod` | 14 | RSI period. |
| `InpRsiBuyMax` / `InpRsiSellMin` | 68 / 32 | RSI stretch limits. |
| `InpUseMtfFilter` | true | Require higher-timeframe agreement. |
| `InpMtfTimeframe` | H1 | Confirmation timeframe. |
| `InpAtrPeriod` | 14 | ATR for arrow offset and leg size filter. |
| `InpArrowOffsetAtr` | 0.60 | Arrow distance from the candle, in ATR. |
| `InpMinLegAtr` | 2.0 | Reject impulses smaller than this many ATR. |

### 10. Signal visuals
| Input | Default | Description |
|---|---|---|
| `InpRevealOnTouch` | true | Keep the entire Fibonacci layer invisible until price reaches the zone. |
| `InpShowBlockZone` | true | Draw the translucent Buy / Sell block over the OTE band. |
| `InpBlockOpacity` | 40.0 | Block opacity as a percentage, blended with the chart background. |
| `InpShowTradePlan` | true | Draw entry / SL / TP lines on the last signal. |
| `InpPlanSlFib` | 1.000 | Retracement level used as the plan's stop loss. |
| `InpPlanTp1Fib` | 1.272 | Extension level used as TP1. |
| `InpPlanTp2Fib` | 1.618 | Extension level used as TP2. |
| `InpShowApproachArrow` | true | Show the `GANN BUY` / `TREND BUY` arrow before price touches the line. |
| `InpApproachAtr` | 0.35 | How close price must be to arm that arrow, in ATR. |
| `InpAnimate` | true | Animate the plan levels and the banner. |
| `InpAnimMs` | 120 | Animation frame time in milliseconds. The dashboard still refreshes once per second. |

### 11. Adrenaline trend banner
| Input | Default | Description |
|---|---|---|
| `InpShowAdrenaline` | true | Show the ADRENALINE ON / OFF banner on a trend flip. |
| `InpAdrenalineFlashSec` | 8 | Seconds of strong flashing after the flip, before it settles. |
| `InpAdrenalineCorner` | Bottom Right | Which corner the banner sits in. |
| `InpAdrenalineX` | 14 | Banner offset from that corner, horizontally, in pixels. |
| `InpAdrenalineY` | 30 | Banner offset from that corner, vertically, in pixels. |

### 8–9. Dashboard and alerts
| Input | Default | Description |
|---|---|---|
| `InpShowPanel` | true | Show the dashboard. |
| `InpPanelCorner` | Top Left | Dashboard corner. |
| `InpPanelX` / `InpPanelY` | 14 / 22 | Offset in pixels from that corner. |
| `InpPanelAnimate` | true | Pulsing live-status dot. |
| `InpAlertPopup` | true | Popup on a new signal. |
| `InpAlertPush` | false | Push notification (requires MetaQuotes ID in Tools → Options → Notifications). |
| `InpAlertSound` | true | Play `InpAlertSoundFile`. |

---

## 4. Dashboard

Dark neon-blue/gold theme, DPI-aware, re-anchors itself on chart resize, and collapses to its title
bar with the `-` button.

* **Header** — symbol, chart timeframe, live spread.
* **Master signal** — the current BUY/SELL state with an 8-segment confluence meter.
* **MTF table** — for M1, M5, M15, M30, H1, H4: EMA trend, RSI, market structure (HH/HL, LH/LL,
  RANGE) and a per-timeframe verdict.
* **Detail rows** — active impulse leg and its size in points, the Golden Zone range plus an
  `[IN ZONE]` flag when price is inside it, the current Gann 1x1 value and whether price is above or
  below it, the nearest Square of 9 levels, and the last signal that fired.
* **Footer** — connection status, pulsing dot, server clock.

---

## 5. Suggested settings

| Style | Timeframe | `InpSwingN` | `InpMinScore` | `InpMtfTimeframe` | Notes |
|---|---|---|---|---|---|
| Scalping | M1 | 3–4 | 6 | M15 | Set `InpMaxBars` to 1500; raise `InpMinLegAtr` to 2.5 to skip noise. |
| Intraday | M5 / M15 | 5 | 5 | H1 | Default profile. |
| Swing | H1 / H4 | 7–10 | 4–5 | H4 / D1 | Enable `InpShowPivots`. |

Suggested trade management: entry inside the Golden Zone, stop below/above the 0.886 level or the
leg origin, targets at the 1.272 / 1.618 extensions.

---

## 6. Performance notes

* Only `InpMaxBars` bars are calculated; the loop uses the `prev_calculated` pattern, so each tick
  recomputes a single bar.
* Chart-object drawing is refreshed only on a new bar or when a swing changes the active leg,
  never on every tick.
* Indicator handles are created once in `OnInit` and released in `OnDeinit`.
* On M1 with a very long history, keep `InpMaxBars` at 1500–3000. Setting it to 0 forces a full
  recalculation on every history reload.
* Object hygiene: everything is created under a per-chart prefix and removed in `OnDeinit`, so
  multiple copies on different charts never collide.

---

## 7. Strategy Tester guidance

The indicator itself has no trades, so test it in **Visual mode** to watch levels and arrows form,
or wrap it in an EA via `iCustom` and test that.

* Modeling: **1 minute OHLC** is enough for bar-close signals; use **Every tick based on real ticks**
  if the EA reacts intrabar.
* The dashboard and drawings are automatically skipped during optimization
  (`MQL_OPTIMIZATION`), so optimization passes stay fast.
* Alerts are suppressed in the tester.
* When testing an EA that reads the buffers, always read shift `1` (the last closed bar) —
  shift `0` is the forming bar and changes within the bar.

---

## 8. Ideas for the next version

* Order blocks, FVG and liquidity-sweep detection layered onto the same impulse leg.
* Gann Square of 9 time cycles (vertical time lines), not just price levels.
* Volume-profile POC/VAH/VAL inside the Golden Zone for confluence.
* Telegram delivery of signals with a chart snapshot.
* Auto-optimising `InpSwingN` from realised volatility instead of a fixed input.
* Session filter (London / New York) and a news blackout window.
