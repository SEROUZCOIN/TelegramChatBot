# FibBot — Fibonacci retracement bot

Finds Fibonacci retracement setups on the chart it is attached to, publishes
them to the platform as signals, and — only if you switch execution on — trades
them with risk-sized position sizing and multi-target management.

It is the method in
[`docs/education/fibonacci-retracement.md`](../../docs/education/fibonacci-retracement.md)
turned into code, including the parts of that document that are warnings.

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
bot analyses and publishes and never sends an order.

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
                        ├─ confirmation close          → TRIGGERED  → publish / trade
                        ├─ close beyond the leg origin → INVALIDATED
                        └─ InpSetupExpiryBars elapsed  → EXPIRED
```

Anchors are **immutable** once armed. A new leg creates a new setup; it never
edits a live one. This is the same discipline
[`packages/shared/src/signal-state.ts`](../../packages/shared/src/signal-state.ts)
applies to signal status, for the same reason — a level that silently moves
after publication is the same integrity failure as a win rate that improves
after the fact.

A setup arms one bar before its zone is evaluated. Given the pivot itself is
already confirmed six bars late by default, one more bar costs nothing and keeps
the rule "state changes only on a closed bar" without exception.

### Confluence factors

All five are non-Fibonacci and mechanically checkable. Whichever fire are named
in the published `analysisText`, so a subscriber sees *why* the setup exists.

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

1. **Allow the URL.** MetaTrader 5 → Tools → Options → Expert Advisors → tick
   *Allow WebRequest for listed URL* and add your API base URL. Skipping this is
   the most common failure; every request returns `-1` with error `4014`.
2. **Create an ingest key.** Admin panel → Settings → MT5 bridge. Paste it into
   `InpIngestKey`. The key is stored hashed and revocable on its own, so a
   compromised VPS never exposes a user account.
3. **Copy the whole `FibBot` folder** into `MQL5\Experts\`, open `FibBot.mq5` in
   MetaEditor and compile (F7). The folder is self-contained and uses relative
   includes, so it compiles from any location under `Experts\`.
4. **Attach one instance per chart.** Unlike `SignalBridge.mq5`, this EA acts on
   the symbol and timeframe of the chart it sits on.

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
| `InpPublishWhen` | ON_ENTRY | ON_SETUP publishes the pending zone as a LIMIT signal instead. |
| `InpMaxDailyLossPct` | 3.0 | Halts for the server day; a new day clears it. |

---

## How it maps onto the platform

It posts the same `signalInputSchema` the admin composer and `SignalBridge.mq5`
post — so this is one more caller of an existing contract, not a second
definition of what a signal is.

| Signal field | What the bot puts there |
|---|---|
| `entryLow` / `entryHigh` | **The Fibonacci zone edges** when publishing on setup |
| `orderType` | `LIMIT` when publishing the zone, `MARKET` at a confirmed entry |
| `sl` | The retracement stop plus its ATR buffer |
| `tp1` / `tp2` / `tp3` | Leg extreme, then the 1.272 and 1.618 extensions |
| `beTrigger` | `tp1` — where the stop is pulled to break-even |
| `analysisText` | Generated: the zone, the anchors, and the confluence that fired |

`entryLow`/`entryHigh` finally carry the meaning the schema always allowed. A
retracement setup has a genuine entry *zone*, where a reported fill (what
`SignalBridge.mq5` sends) collapses to a single price.

Updates posted to `/ingest/signals/updates`: `ENTRY_HIT`, `MOVED_TO_BE`,
`TP1_HIT`, `TP2_HIT`, `TP3_HIT`, `SL_HIT`, `CLOSE_WIN`, `CLOSE_LOSS`,
`CANCELLED`. The break-even report is the one that matters most for honesty:
the platform scores a stop-out *after* a break-even move as a scratch rather
than a loss, so publishing that event is what keeps the win rate truthful.

**One live signal per symbol.** The ingest endpoint matches an update to the
most recent open signal for that symbol, so running two instances on the same
instrument makes updates ambiguous. One chart per symbol.

---

## Backtesting it

`WebRequest` is disabled in the Strategy Tester, so the whole API layer no-ops
there and the strategy runs unchanged. That is the point: the trading logic is
testable in isolation.

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

They are complements and can run side by side, on different charts.

| | `SignalBridge.mq5` | `FibBot` |
|---|---|---|
| Source of signals | Trades **you** place manually | Setups it finds itself |
| Opens positions | Never | Only if `InpEnableTrading` |
| Scope | The whole terminal | One chart's symbol |
| Entry field | A single fill price | A zone, when publishing on setup |

If you run both, give them different symbols — otherwise two callers publish
signals for the same instrument and the update matching becomes ambiguous.
