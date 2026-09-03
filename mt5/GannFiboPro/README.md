# GannFiboPro — MT5 Indicator

Gann Fan + Auto Trendlines + Fibonacci Golden Zone (OTE) + Gann Square of 9 + Classic Pivots,
with confluence-scored Buy/Sell arrows and a futuristic multi-timeframe dashboard.

Single file, zero dependencies: `GannFiboPro.mq5`.

A companion martingale EA that trades these levels ships alongside it —
see **[README-EA.md](README-EA.md)** for `GannFiboProEA.mq5`.

---

## 1. Installation

1. Copy `GannFiboPro.mq5` into `MQL5\Indicators\GannFiboPro\` inside your terminal data folder
   (MetaTrader 5 → **File → Open Data Folder**).
2. Open it in MetaEditor and press **F7** (Compile). Expect `0 errors, 0 warnings`.
3. In MT5, refresh the Navigator (right-click → Refresh), then drag **GannFiboPro** onto a chart.
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

**Non-repainting:** arrows are written only to closed bars (`rates_total − 2` and older) and swings
are only confirmed from closed bars, so an arrow never appears and disappears on the same bar.
The drawn *levels* do move when a new swing confirms — that is the intended behaviour of any
auto-Fibonacci/Gann tool, not repainting of the signals.

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
int h = iCustom(_Symbol, PERIOD_CURRENT, "GannFiboPro\\GannFiboPro");  // defaults
double sig[1], zoneHi[1];
CopyBuffer(h, 2, 1, 1, sig);      // signal on the last closed bar
CopyBuffer(h, 5, 0, 1, zoneHi);   // live Golden Zone upper bound
```

Buffers 4–7 exist so an EA never has to re-derive the swing/leg/zone logic — the
bundled `GannFiboProEA.mq5` reads exactly these.

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
| `InpShowGoldenZone` | true | Draw the OTE box. |
| `InpGZ_Start` / `InpGZ_End` | 0.618 / 0.786 | Golden Zone bounds. Use 0.618 / 0.650 for the strict pocket. |
| `InpShowGoldenPocket` | true | Highlight 0.618–0.650. |
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
