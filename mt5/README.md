# MetaTrader 5 bridge

`SignalBridge.mq5` publishes trades opened on your MT5 terminal to the platform
as signals. It only reports — it never opens, modifies, or closes a position.

## Why this exists as a separate piece

The admin composer and this EA post the **same payload** (`signalInputSchema` in
`packages/shared`). Defining that contract before either caller existed is what
makes the auto-feed additive: turning it on adds a caller, it does not change
the server or the composer.

## Setup

1. **Allow the URL.** MetaTrader 5 → Tools → Options → Expert Advisors → tick
   *Allow WebRequest for listed URL* and add your API base URL. Skipping this is
   the single most common failure; every request returns `-1` with error `4014`.

2. **Create an ingest key.** Admin panel → Settings → MT5 bridge. The key is
   shown once and stored only as a hash. It authenticates the bridge alone, so
   revoking a compromised VPS does not touch any user's login.

3. **Compile and attach.** Copy the file to `MQL5/Experts/`, compile in
   MetaEditor (F7), and attach it to any one chart. It watches the whole
   terminal, not the chart it sits on, so one instance covers every symbol.

## Inputs

| Input | Meaning |
|---|---|
| `InpApiBaseUrl` | API base, e.g. `https://api.example.com/api` |
| `InpIngestKey` | The key from the admin panel |
| `InpMinPlan` | Tier that receives these signals (default `SIGNALS`) |
| `InpPublishNow` | Publish immediately, or leave as a draft to review first |
| `InpReportUpdates` | Report break-even moves as they happen |
| `InpPollSeconds` | Position poll interval |

## Behaviour worth knowing

- **Positions open when you attach the EA are adopted, not republished.** Only
  trades opened from that point on are sent.
- **A position without both a stop and a target is skipped.** The API requires
  both, and a signal without them is not actionable for a subscriber anyway.
- **Break-even detection.** When your stop moves to the entry price (within a
  20-point tolerance), the EA reports `MOVED_TO_BE`. This matters for accuracy
  rather than decoration: the platform scores a later stop-out *after* a
  break-even move as a scratch rather than a loss, so the published win rate
  stays honest.

---

# CSI-Omega indicator

`CSI_Omega.mq5` scores swing legs and calls continuation or reversal between
them. It is independent of the signal bridge — an analysis tool, not a feed.

## What it does

Each candle inside a swing leg is awarded a score by its class rather than
counted as one unit. Those scores accumulate, signed, into a leg total (`CNS`),
which resolves into three normalised sub-scores (`CS`, `SP`, `NP`) and collapses
into one `0..100` leg strength (`CSI`). Two consecutive opposing legs are then
fused (`CD`) into a verdict anchored at a reference price (`RP`).

The derivation, the calibration against the reference charts, and the two
places where the source method was under-specified are in
[`docs/CSI-MODEL.md`](../docs/CSI-MODEL.md). Read that before changing a
default — several of them are load-bearing.

## Setup

Copy to `MQL5/Indicators/`, compile in MetaEditor (F7), attach to a chart. No
network access, no keys, nothing to configure to get a first reading.

## Reading it

The subwindow plots `CSI` (gold line) and `CD` (blue histogram). The on-chart
panel shows the live leg, the last scored leg's components, the fusion, and the
verdict with its reference and invalidation levels. Each scored pivot is
labelled `CNS | CSI`.

## Inputs worth knowing

| Input | Meaning |
|---|---|
| `InpDevMultiplier` | Swing confirmed after this many ATR of retracement. The single most important setting — it defines what counts as a leg. |
| `InpScore*` / `InpBody*` | The per-candle score table. Replaceable wholesale without touching code. |
| `InpSpReference` | Efficiency ratio that scores `SP = 100`. Below ~0.5 this saturates and `SP` stops discriminating. |
| `InpWeightCS/SP/NP` | The `0.5 / 0.3 / 0.2` collapse. Should sum to 1; the indicator warns if not. |
| `InpReversalRatio` | `CSI(new)/CSI(prev)` at or above this reads as a reversal. Centred on parity at `1.10`, not on the source method's `0.85` — see `docs/CSI-MODEL.md` §6 for the measured distribution that forced it. |
| `InpContinuationRatio` | At or below this, the counter-leg was only a pullback. |
| `InpMinCD` | Below this fused score, no verdict is issued at all. |

## Behaviour worth knowing

- **A leg is scored only once its terminating swing is confirmed.** Confirmation
  lags the real pivot by design. Once written, a value is never revised, so the
  plot does not repaint.
- **The live leg appears in the panel only**, never in a buffer — an unconfirmed
  leg has no score yet.
- **Alerts fire only on the newest bars**, never while the indicator walks back
  through history on attach.
- **Buffers 2–4 carry `CNS`, the verdict code, and the leg direction** for
  `iCustom` consumers, so an EA can read the verdict without re-deriving it.

---

# CSI-Omega Pro

`CSI_Omega_Pro.mq5` is the trading surface of the same model: entry arrows,
structural levels, multi-timeframe confluence and a dashboard. The scoring
lives in `Include/CSIOmega.mqh` and is shared with `CSI_Omega.mq5`, so the
formula cannot drift between the two.

## Setup

Copy `Include/CSIOmega.mqh` to `MQL5/Include/` and `CSI_Omega_Pro.mq5` to
`MQL5/Indicators/`, then compile the indicator in MetaEditor (F7). The include
must be in place first or the compile fails on the `#include` line.

## What it draws

| | |
|---|---|
| Arrows | One per actionable verdict, at the confirmation bar |
| Entry / stop / TP1–TP3 | Horizontal lines for the most recent signal |
| Leg labels | `CNS \| CSI` at each scored pivot |
| Dashboard | Confluence, the three sub-scores as gauges, `CSI`/`CD`, the verdict, the last signal, and a measured hit rate |

## Inputs worth knowing

| Input | Meaning |
|---|---|
| `InpMinCSI` | Floor on the new leg's own strength before it may signal. The main selectivity dial. |
| `InpUseMtf`, `InpMtf1..3` | Run the whole model on up to three higher timeframes. Each is scanned only when that timeframe prints a new bar. |
| `InpRequireMtf`, `InpMtfMinAgree` | Block signals that lack higher-timeframe agreement. Off by default — turn it on to trade less and later. |
| `InpSlAtrBuffer` | How far beyond the structural level the stop sits. |
| `InpMinStopAtr` | Floor on risk. Only ever widens a stop, never tightens it. |
| `InpTp1R`–`InpTp3R` | Targets as multiples of the measured risk. |

## Behaviour worth knowing

- **The stop is structural, and which structure depends on the verdict.** A
  reversal is invalidated by the leg's origin; a continuation by the pivot the
  leg just failed at. Getting this wrong puts a long's stop above its entry —
  see `docs/CSI-MODEL.md` §6.
- **A signal whose risk cannot be stated is not drawn.** If the geometry puts
  the stop on the wrong side of entry, the bar is skipped rather than guessed.
- **The hit rate on the panel is measured, not assumed.** It counts the
  indicator's own confirmed signals over the calculated history, resolving each
  at whichever of TP1 or the stop is touched first, and scores a bar that spans
  both as a loss.
- **Every bar is processed exactly once, after it closes.** The forming bar is
  never fed to the engine, so arrows never move.
- **No edge is claimed.** The defaults are principled, not fitted, and have
  been validated for mechanics only. Backtest before trading.
