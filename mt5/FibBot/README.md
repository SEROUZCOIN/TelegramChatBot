# FibBot — Fibonacci retracement bot

Finds Fibonacci retracement setups on the chart it is attached to, draws them,
and — only if you switch execution on — trades them with risk-sized position
sizing and multi-target management.

It is the method in
[`docs/education/fibonacci-retracement.md`](../../docs/education/fibonacci-retracement.md)
turned into code, including the parts of that document that are warnings.

**It is self-contained.** No network, no API, no keys, no URL whitelisting. Copy
it in, compile, attach.

---

## What it will not do

Three refusals are deliberate, because each one is a way Fibonacci automation
usually fools its author:

- **It never reads the forming bar.** A swing pivot is confirmed only after
  `InpPivotRight` bars have closed to its right. That lag is inherent to an
  objective definition, not a bug — nothing here uses ZigZag, whose final leg is
  provisional and repaints, and which therefore cannot be backtested honestly.
- **It never enters on a touch of a level.** By default a setup needs a
  confirmation close: a bar that traded into the zone and closed back out of it
  in the trade direction. The zone says *where*, the trigger says *when*.
- **It never arms on a Fibonacci level alone.** A setup requires
  `InpMinConfluence` independent, **non-Fibonacci** factors. Two Fibonacci levels
  landing together are one factor, not two — they are not independent evidence.

**Execution is off by default** (`InpEnableTrading = false`). Out of the box the
bot finds and draws setups and never sends an order. Watch it mark up your
charts for a while before you let it trade.

---

## The pipeline

Every transition is decided by a **closed** bar, and no transition may consult a
bar later than the one being processed.

```
IDLE
 └─ pivot confirmed (InpPivotRight bars closed)
    and leg ≥ InpMinLegAtr × ATR
    and confluence ≥ InpMinConfluence
         → ARMED            anchors frozen, levels computed once
              └─ a bar's extreme trades into the entry zone
                   → IN_ZONE
                        ├─ confirmation close          → TRIGGERED  → trade
                        ├─ close beyond the leg origin → INVALIDATED
                        └─ InpSetupExpiryBars elapsed  → EXPIRED
```

Anchors are **immutable** once armed. A new leg creates a new setup; it never
edits a live one. A level that silently moves after you have acted on it is not
a level.

A setup arms one bar before its zone is evaluated. Given the pivot itself is
already confirmed six bars late by default, one more bar costs nothing and keeps
the rule "state changes only on a closed bar" without exception.

### Confluence factors

All five are non-Fibonacci and mechanically checkable. Whichever fire are named
in the journal line when the setup arms, so you can see *why* it exists.

| Factor | Fires when |
|---|---|
| `trend` | The leg agrees with an EMA on `InpTrendTimeframe` |
| `structure break` | The leg's extreme exceeded the prior same-side swing |
| `prior swing in zone` | An earlier confirmed pivot sits inside the entry band |
| `round number` | A multiple of `InpRoundStepPoints` falls inside the band |
| `displacement bar` | The leg contains a bar ≥ `InpDisplaceAtr` × ATR |

---

## Geometry, and why the defaults are what they are

With the entry at retracement `r`, the stop at the leg origin, and the first
target at the leg extreme:

```
R = r / (1 − r)          break-even win rate = 1 − r
```

The default zone is 61.8%–78.6%, which is 1.62R to 3.67R and needs a 38.2% or
21.4% win rate respectively. Those are not free: the break-even win rate is
*exactly* `1 − r`, so entering deeper buys payoff at precisely the price of
probability. **The ladder is edge-neutral, and costs make it negative.** The
confluence gate and the trigger are what have to carry the edge, which is why
they are not optional and why `InpMinConfluence` should not be set to 0.

`InpStopFib` is validated to be at least `InpEntryFibFar` at load: a stop
shallower than the deep edge of your own entry zone gets hit before the setup
has been tested.

---

## Setup

1. **Copy it in.** Either the whole `FibBot` folder into `MQL5\Experts\`, or just
   `FibBot_AllInOne.mq5` — same code, one file, easier to paste.
2. **Compile.** Open `FibBot.mq5` (or the all-in-one) in MetaEditor, press **F7**.
3. **Attach one instance per chart.** It acts on the symbol and timeframe of the
   chart it sits on.

That is all. There is nothing to configure before it runs.

---

## Inputs worth understanding

| Input | Default | Why it matters |
|---|---|---|
| `InpPivotLeft` / `InpPivotRight` | 5 / 5 | Swing strictness. `Right` **is** the confirmation lag in bars. |
| `InpMinLegAtr` | 2.0 | Rejects legs that are drift rather than impulse. |
| `InpEntryFibNear` / `Far` | 0.618 / 0.786 | The entry band. This is the ICT "optimal trade entry" range. |
| `InpStopFib` | 1.0 | 1.0 = the leg origin. Must be ≥ `InpEntryFibFar`. |
| `InpStopAtrBuffer` | 0.5 | Never tuck a stop right behind a level everyone can see. |
| `InpMinConfluence` | 2 | The gate that has to carry the edge. Do not set to 0. |
| `InpRequireTrigger` | true | Off = enter on touch. Turning this off is how the strategy usually stops working. |
| `InpEnableTrading` | **false** | Execution opt-in. |
| `InpRiskPercent` | 1.0 | Sized from the real stop distance, never from a fixed lot. |
| `InpBeAtTp1` | true | Stop to break-even once the first target fills. |
| `InpMaxDailyLossPct` | 3.0 | Halts for the server day; a new day clears it. |

---

## Backtesting it

The bot talks to nothing external, so it runs in the Strategy Tester exactly as
it runs live. That is the point.

What the document asks you to test is not "is this profitable" but:

> **Does the level hold more often than `1 − r`?**

Run it, then run it again with `InpEntryFibNear`/`Far` set to arbitrary
non-Fibonacci fractions — 0.44, 0.57, 0.71. If the Fibonacci settings do not
separate from those controls, your edge is in the trend filter and the trigger,
not in the ratio. That is a useful result, and it changes what is worth
optimising.

Other hygiene, all of which this design already supports:

- Use **Every tick based on real ticks** where available. The partial-close and
  break-even logic runs intrabar and open-prices modelling will not exercise it.
- Cover at least five years including trends, chop, and one volatility break.
- Do not co-optimise `InpPivotRight`, `InpMinLegAtr`, and the entry fractions on
  one sample. Walk forward.
- Setups where price never reached the zone are part of the sample. `OnTester`
  returns 0 below 30 trades so tiny samples cannot win an optimisation.
- Synthetic indices with engineered spikes (Boom/Crash and similar) have
  retracement statistics unrelated to FX. Never carry parameters across
  instrument classes without re-testing.

---

## Accounts and limits

- **Netting and hedging both work.** The bot keeps at most one position per
  symbol and closes partials through `CTrade::PositionClosePartial`. On a netting
  account, do not run another EA on the same symbol — the positions merge and
  the partials will act on volume that is not yours.
- **A position adopted after a restart is left alone.** Without the setup that
  created it the bot has no targets to manage, so it defers to the broker-side
  stop and target rather than guessing.
- A partial is skipped when it would leave a remainder below the broker's
  minimum volume. A risk-sized lot below the minimum **skips the trade** rather
  than silently rounding up, which would break the risk model.

---

## Relationship to `SignalBridge.mq5`

Unrelated, and they can run side by side. `SignalBridge.mq5` publishes trades
*you* place to the platform API for your subscribers. FibBot finds its own
setups and reports to nobody.

If you ever want FibBot's setups on the subscriber feed, that wiring existed and
was removed deliberately — `git log` has it, and reverting the commit that
removed it brings it back intact.
