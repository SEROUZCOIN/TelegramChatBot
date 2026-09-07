# Neuro Gann Zones — MetaTrader 5 indicator

An advanced W.D. Gann analysis suite for MT5 that draws **zones and up/down lines
directly on the chart** and reduces three independent engines to one directional
reading.

| Engine | What it contributes |
|---|---|
| **Gann geometry** | nine-ray fan (1x8 … 8x1), Square of Nine, eighths & thirds, time cycles, confluence zones |
| **Mathematics** | least-squares regression + R², Kaufman efficiency ratio, z-score, Wilder RSI/ATR, variance ratio, volatility regime, ATR-normalised momentum, directional volume |
| **Neural layer** | a multilayer perceptron (12 → hidden → 1, tanh) trained by SGD on closed historical bars |

---

## 1. Installation

1. Copy the whole `NeuroGannZones` folder into
   `<MT5 data folder>/MQL5/Indicators/`
   (File → Open Data Folder in the terminal).
2. Open `NeuroGannZones.mq5` in MetaEditor and press **F7**.
3. Drag the compiled indicator onto any chart.

The folder is self-contained and location-independent: every project include uses
a quoted relative path, so you can move or rename the folder anywhere under
`MQL5/Indicators/` and it still compiles. No files are installed into
`MQL5/Include/`.

```
NeuroGannZones/
   NeuroGannZones.mq5   entry point: buffers, OnCalculate, events
   NGZ_Config.mqh       CONFIG  - inputs, enums, THEME colours, METRICS
   NGZ_State.mqh        STATE   - the two runtime globals, anchors, network struct
   NGZ_Math.mqh         CORE    - the mathematical library (no handles, no CopyBuffer)
   NGZ_Gann.mqh         CORE    - the Gann geometry engine
   NGZ_Neuro.mqh        CORE    - forward pass, backprop, persistence
   NGZ_Draw.mqh         UI      - price/time drawings (candle-anchored)
   NGZ_Panel.mqh        UI      - the neon dashboard (pixel-anchored)
```

---

## 2. What appears on the chart

### Lines

| Element | Meaning |
|---|---|
| **NeuroGann Trend** (thick, colour-changing) | the regression baseline biased by the fused score — green above the neutral band, red below, grey inside it |
| **Gann UP line 1x1** (green) | the 45° rail rising from the last confirmed swing **low**. While price closes above it, the up-trend is intact by Gann's own definition. The line stops the moment a bar *closes* below it. |
| **Gann DOWN line 1x1** (red) | the mirror rail falling from the last confirmed swing **high** |
| **Fan rays** | 1x8, 1x4, 1x3, 1x2, **1x1**, 2x1, 3x1, 4x1, 8x1 from each anchor, labelled with their true geometric angle |
| **Square of 9 levels** | horizontal rays at ±45°, ±90° … around the active anchor; the 90/180/270/360 rotations are drawn solid |
| **Gann eighths & thirds** | 1/8 … 7/8 plus 1/3 and 2/3 of the master swing; the 50 % pivot is gold |
| **Time-cycle verticals** | at 45, 90, 144, 180, 225, 270, 360 bars from the anchor (configurable) |

### Zones

| Zone | Colour | Meaning |
|---|---|---|
| **Power zone** | deep green / deep red | the band between the 1x1 and 2x1 rays — trend acceleration |
| **Balance zone** | dim green / dim red | the band between 1x2 and 1x1 — the healthy trend channel |
| **Premium / Discount** | red above / green below | the two halves of the master swing, split by the equilibrium line |
| **Time-cycle bands** | amber vertical strips | the ± tolerance window around each Gann cycle date |
| **Confluence zones** | orange | where a Square-of-9 level lands on a fan ray — price geometry and time geometry agreeing on the same number |
| **Projection zone** | green / red box to the right | the fused score scaled by Gann travel over the next N bars |

### Dashboard

Dark HUD with neon-blue and gold accents: instrument, bias, fused score, the three
module scores with signed gauges, the live 1x1 unit in points per bar, both
anchors, both rails, the bracketing Square-of-9 levels, the next time cycle,
premium/discount state, network diagnostics and the last confirmed signal.
Five buttons (`FAN`, `SQ9`, `ZONE`, `CYCL`, `1/8`) toggle each drawing layer live,
and `-` collapses the panel.

---

## 3. Trading logic

**Anchors.** A swing pivot at bar *p* is only confirmed *N* bars later
(`InpSwingBars`), so an anchor never appears earlier than the market could have
seen it. When an anchor is created, the price/time unit is **frozen** on it —
every ray and rail derived from that anchor keeps its slope forever.

**The 1x1 rail.** Gann's central claim is that the 45° line is the trend: while
price holds above the line rising from a low, the up-trend stands. The indicator
implements exactly that — the rail is published bar by bar and is killed by the
first *close* on the wrong side of it (intrabar wicks never kill a rail).

**The scale.** Everything in Gann depends on how much price one bar of time is
worth. Four modes:

* `ATR` (default) — unit = ATR × `InpAtrFactor`, adaptive per instrument
* `Range / Bars` — the statistical slope of the lookback window
* `Chart geometry` — the unit that makes the 1x1 ray render at a visual 45° on
  *your* chart at *your* zoom; the fan is rebuilt when you rescale
* `Manual` — points per bar

**Square of Nine.** One full 360° turn of the wheel adds `InpSq9Turn` to the
square root of the price (2.0 = the classic wheel, 1.0 = the intraday variant).
Raw FX prices are far too small for the wheel, so the price is scaled up by
10^Digits before the root and scaled back afterwards; results are rounded to the
instrument's tick size so every level is a tradeable price.

**Mathematical consensus.** Ten normalised features are combined with fixed,
visible weights (`NGZ_W_*` in `NGZ_Config.mqh`) — trend-following features add,
mean-reversion features subtract. Nothing is hidden.

**Neural layer.** The twelve features of every bar are cached, then the network is
trained once per history on samples whose future is fully known: the target is the
forward move over `InpHorizon` bars squashed by `tanh(move / (ATR × InpTargetATR))`.
The RNG seed is an input, so the same history always yields the same weights.

**Fusion & signals.** `score = wNeuro·neuro + wMath·math + wGann·gann`, clamped to
[-1, +1]. A buy arrow prints when the score crosses **up** through
`InpSignalLevel`; a sell arrow when it crosses **down** through `-InpSignalLevel`.
With `InpRequireRail` on, a buy also needs price on the right side of the live 1x1
up-rail (and vice versa).

### Repainting policy

**Non-repainting by construction, with one honest caveat.**

* Arrows are written only to bars with index `< rates_total-1`; the forming bar
  never receives a signal.
* Anchors are created only from closed bars, after their confirmation delay.
* Rails use the unit frozen at anchor creation, so historical rail values never
  move — *in `ATR` and `Manual` scale modes*.
* In `Range / Bars` and `Chart geometry` scale modes the unit is global and live,
  so historical rays shift when the window or the zoom changes. That is inherent
  to those modes; use `ATR` if you need a frozen history.
* The network is trained once per loaded history. Reloading history or changing
  an input retrains it, which can shift the *trend line* (not the arrows'
  crossing rule) — the seed makes this deterministic and reproducible.

---

## 4. Input reference

### 1. Engine
| Input | Meaning |
|---|---|
| `InpMode` | `FUSION` (all three), or `NEURO` / `MATH` / `GANN` alone |
| `InpWeightNeuro / Math / Gann` | fusion weights; normalised internally, so any scale works |
| `InpMaxBars` | how many recent bars to score (0 = all). Caps both CPU and the feature cache |

### 2. Gann geometry
| Input | Meaning |
|---|---|
| `InpAnchorMode` | `SWING` (confirmed fractal pivots), `EXTREME` (highest/lowest of the lookback), `MANUAL` (fixed date) |
| `InpSwingBars` | pivot strength — bars required on each side. Higher = fewer, larger anchors, longer confirmation delay |
| `InpSwingLookback` | master-range window; drives premium/discount and the range scale |
| `InpScaleMode`, `InpAtrFactor`, `InpManualUnit` | the price/time unit (see above) |
| `InpFanLength` | ray projection length in bars; rays are rays, so they extend past it |
| `InpShowFan`, `InpShowFanLabels`, `InpDualFan` | fan visibility |

### 3. Square of 9
`InpShowSq9`, `InpSq9Turn` (2.0 classic / 1.0 intraday), `InpSq9Step` (degrees per
level), `InpSq9Levels` (levels each side), `InpSq9ScaleMode` + `InpSq9ScaleManual`.

### 4. Eighths & time cycles
`InpShowRetrace`, `InpShowCycles`, `InpCycleList` (comma-separated bar counts),
`InpCycleBand` (band half-width in bars).

### 5. Zones
`InpShowZones` (master switch), `InpShowFanZones`, `InpShowPremium`,
`InpShowConfluence`, `InpShowProjection`, `InpConfluenceATR` (confluence tolerance
in ATR), `InpProjectBars`.

### 6. Mathematics
Periods for regression, ATR, ATR baseline, RSI, efficiency ratio, z-score,
momentum, variance ratio (+ lag) and volume regression.

### 7. Neural network
`InpUseNeuro`, `InpHidden` (2–32), `InpTrainBars`, `InpEpochs`, `InpLearnRate`,
`InpLrDecay`, `InpL2`, `InpHorizon`, `InpTargetATR`, `InpNetSeed`,
`InpMinSamples`, `InpPersistNet` (store weights in the common `Files` folder).

### 8. Signals & alerts
`InpSignalLevel`, `InpExitLevel` (neutral band), `InpRequireRail`, `InpTrendAmp`,
`InpRailBars`, and the four alert channels (popup / push / mail / sound).

### 9. Dashboard
`InpShowPanel`, `InpPanelCorner`, `InpPanelX`, `InpPanelY`, `InpPanelDpi`.

---

## 5. Consuming it from an EA

| Buffer | Contents |
|---|---|
| 0 | NeuroGann trend line (price) |
| 1 | trend colour index — 0 flat, 1 up, 2 down |
| 2 | Gann **UP** 1x1 rail (`EMPTY_VALUE` when no valid rail) |
| 3 | Gann **DOWN** 1x1 rail |
| 4 | buy arrow price (`EMPTY_VALUE` when no signal) |
| 5 | sell arrow price |

```mql5
int h = iCustom(_Symbol, PERIOD_CURRENT, "NeuroGannZones\\NeuroGannZones");
// ... in OnInit only, then read with CopyBuffer(h, 4, 1, 1, buf) for the last closed bar
```

Ship it inside the EA with `#resource "NeuroGannZones.ex5"` +
`iCustom(..., "::NeuroGannZones.ex5", ...)` to keep the EA self-contained.
Note that on current builds each `input group` line occupies a slot in the
`params[]` array of `IndicatorCreate()` — count them if you build the parameter
array by hand.

---

## 6. Performance and tuning

* One full pass costs `O(InpMaxBars × InpSwingLookback)`. On a chart with deep
  history keep `InpMaxBars` at 3000–6000; incremental ticks then cost almost
  nothing because only the forming bar is recomputed.
* ATR and RSI are computed as Wilder recurrences inside the indicator — no
  indicator handles, no `CopyBuffer`, no multi-timeframe synchronisation traps.
* The dashboard refreshes at most every 400 ms; drawings are rebuilt only on a new
  bar, a layer toggle, or a real chart resize.
* Training cost is `InpEpochs × samples × InpHidden × 12`. The defaults
  (40 × 2500 × 10) take well under a second.
* On a VPS, prefer `InpScaleMode = ATR` — the chart-geometry mode needs a laid-out
  chart and falls back to ATR when the chart cannot be measured.

### Where to start optimising

1. `InpSwingBars` (5–15) — this changes the geometry more than anything else.
2. `InpAtrFactor` (0.3–1.0) — the 1x1 slope.
3. `InpSignalLevel` (0.25–0.55) with `InpExitLevel` about a third of it.
4. `InpHorizon` (3–15) matched to your holding time, and `InpTargetATR` (0.8–2.0).
5. Fusion weights last, once the three engines each look sane alone
   (`InpMode = GANN`, then `MATH`, then `NEURO`).

## 7. Strategy Tester notes

The indicator is tester-safe: alerts and drawings are suppressed under
`MQL_OPTIMIZATION`, and no chart-dependent call is required for the default ATR
scale. To evaluate it, wrap it in an EA that reads buffers 4 and 5 on the last
closed bar, and test in **Every tick based on real ticks** with a modelling
window long enough to cover `InpMaxBars` plus the warm-up. Because the network
trains on the visible history, a walk-forward run is the honest test: optimise on
one window, validate on the next without re-optimising.

## 8. Ideas for the next version

* Multi-timeframe confluence: score the same geometry on H4/D1 and require agreement.
* Persist one trained network per symbol/timeframe and hot-reload it (the file
  format is already in place behind `InpPersistNet`).
* Replace the plain MLP with a small GRU over the feature sequence, or export an
  ONNX model and run it through `OnnxRun`.
* Add Gann's angle-from-price square (144/90/52) as a fourth geometric feature.
* Telegram/webhook delivery of signals through a service program.
* A companion EA with risk-based sizing, break-even, partial close and a session
  filter driven by buffers 2–5.
