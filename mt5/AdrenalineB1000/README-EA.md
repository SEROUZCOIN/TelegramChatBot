# Adrenaline B1000 EA — Martingale EA for the Adrenaline B1000 indicator

**Author: Serro Deriv**

`AdrenalineB1000EA.mq5` trades the levels that [`AdrenalineB1000`](README.md) draws. It reads the
indicator through `iCustom` — it does **not** re-implement the swing, Gann or Fibonacci logic, so
the chart and the EA can never disagree.

No session filter, no time filter, no news filter — as requested. The input list stays short.

---

## 1. Installation

1. Compile the **indicator first**: `MQL5\Indicators\AdrenalineB1000\AdrenalineB1000.mq5` → F7.
   The EA cannot start without `AdrenalineB1000.ex5` existing.
2. Copy `AdrenalineB1000EA.mq5` into `MQL5\Experts\AdrenalineB1000\` and compile it → F7.
3. Enable **Algo Trading** in the terminal toolbar.
4. Drag the EA onto a chart. Attaching the indicator to the same chart is optional — the EA loads
   its own instance either way — but you will want it visible to see what the EA is reacting to.
5. `InpIndName` must match where the indicator lives, relative to `MQL5\Indicators` and without the
   extension. Default: `AdrenalineB1000\AdrenalineB1000`.

**Account type.** Designed for **hedging** accounts, where each martingale add is its own position.
It also runs on **netting** accounts — the adds merge into a single position and the average price
stays correct — but you lose per-rung visibility. The EA logs which mode it detected on start.

---

## 2. How it trades

One **cycle** = one basket of same-direction positions, opened, managed and closed together.

### Entry 1 — Golden Zone reached (*before* the arrow)
The first position opens once price reaches the **discount region** of the active impulse leg —
ahead of the indicator's arrow confirmation. This is the early, cheap entry.

* Up leg → price pulls back to the 0.618 level or deeper, while still above the 1.000 origin → **BUY**.
* Down leg → price rallies to the 0.618 level or higher, while still below the 1.000 origin → **SELL**.
* Fires **once per leg**. Once a leg has been traded it will not trigger again on that leg, whether
  or not the cycle is still open.
* Toggle with `InpEntryZoneTouch`.

**Why "reached" and not "inside the 0.618–0.786 band".** The indicator only confirms a swing
`InpSwingN` bars *after* it printed, so on a fast pullback price can travel through the whole
0.618–0.786 band before the leg even becomes visible to the EA. Requiring price to be strictly
inside that band at the moment the EA looks means the gate is almost never open, and the EA takes
no trades at all. The condition is therefore "price has reached the 0.618 edge and the leg is
still valid", which spans 0.618 → 1.000. The chart status shows `[IN ZONE]` when price is strictly
inside the band and `[DISCOUNT - entry armed]` when it is past it but still inside the leg.

### Entry 2 — the arrow
When the indicator prints an arrow (score ≥ `InpMinScore`), the EA opens the **next martingale
rung** in the same direction. If no basket exists yet, the arrow starts one at the base lot.

* An **opposite** arrow closes the whole basket when `InpCloseOnReverse` is on.
* Each arrow bar is consumed once, so one arrow never opens two positions.
* Toggle with `InpEntryOnArrow`.

### Entry 3 — distance martingale
While the basket is open, every time price moves `InpStepPoints` **against** the last entry, another
rung opens. With `InpStepGrow` on, the required distance widens at each level
(`step × level`), which keeps the ladder from filling too fast in a fast move.

### The lot ladder
Every rung multiplies the previous lot by `InpLotMult`:

| Level | Lot with base 0.01 and multiplier 2.0 | with 3.0 |
|---|---|---|
| 1 (zone touch) | 0.01 | 0.01 |
| 2 (arrow) | 0.02 | 0.03 |
| 3 | 0.04 | 0.09 |
| 4 | 0.08 | 0.27 |
| 5 | 0.16 | 0.81 |

`InpLotMult` is clamped to a hard maximum of **5.0** in code; anything higher is reduced and logged.
`InpMaxTrades` caps the number of rungs per cycle. Every lot is normalised to the symbol's volume
step and checked against free margin before sending — a rung that cannot be afforded is skipped and
logged rather than sent and rejected.

### Exits
All exits work off the **basket average price**, recomputed after every add:

* **Take profit** — `InpTakeProfit` points from the average. Written to every position as a
  broker-side TP *and* enforced by the EA, so it still works if the broker rejects the level.
* **Stop loss** — `InpStopLoss` points from the average. `0` disables it (the equity stop below is
  then your only floor).
* **Break-even** — after `InpBreakEvenAt` points of basket profit, the stop moves to the average
  plus `InpBreakEvenLock` points.
* **Trailing** — arms at `InpTrailStart` points of basket profit, then follows price at
  `InpTrailDistance`, ratcheting only forward and only when it improves by at least
  `InpTrailStep` (this is what keeps the EA from hammering the server with modifications).
* **Opposite arrow** — closes the basket when `InpCloseOnReverse` is on.

Break-even and trailing both write to the same stop; whichever is further along wins. An existing
stop is never cleared, only improved.

### Circuit breaker
`InpEquityStopPct` closes everything and **halts** the EA once equity falls that far below its peak.
This is the one protection a martingale genuinely needs. It stays halted until you remove and
re-attach the EA. Set it to `0` to disable — not recommended.

---

## 3. Input reference

### 1. Indicator link
| Input | Default | Description |
|---|---|---|
| `InpIndName` | `AdrenalineB1000\AdrenalineB1000` | Path under `MQL5\Indicators`, no extension. |
| `InpMinScore` | 5 | Minimum confluence score (0–8) for the EA to act on an arrow. |

The EA calls the indicator with its **default settings**. To trade a different configuration —
a narrower Golden Zone, a different swing strength — edit the indicator's own defaults and
recompile it; the EA then follows automatically.

### 2. Direction
| Input | Default | Description |
|---|---|---|
| `InpDirection` | Buy and Sell | **Buy only** / **Sell only** / both. |

### 3. Entries
| Input | Default | Description |
|---|---|---|
| `InpEntryZoneTouch` | true | Entry 1: Golden Zone touch, before the arrow. |
| `InpEntryOnArrow` | true | Entry 2: indicator arrow. |

At least one must be on, or `OnInit` refuses to start.

### 4. Martingale
| Input | Default | Description |
|---|---|---|
| `InpLotStart` | 0.01 | Base lot for the first position. |
| `InpLotMult` | 2.0 | Multiplier per rung. Clamped to 5.0. |
| `InpMaxTrades` | 5 | Maximum rungs per cycle. |
| `InpStepPoints` | 250 | Distance between distance-based adds. `0` = arrow adds only. |
| `InpStepGrow` | true | Widen the step at each level. |

### 5. Exits
| Input | Default | Description |
|---|---|---|
| `InpTakeProfit` | 300 | Basket TP from the average, in points. `0` = off. |
| `InpStopLoss` | 0 | Basket SL from the average, in points. `0` = off. |
| `InpCloseOnReverse` | true | Close the basket on an opposite arrow. |

### 6. Trailing
| Input | Default | Description |
|---|---|---|
| `InpUseTrailing` | true | Enable basket trailing. |
| `InpTrailStart` | 150 | Basket profit in points before trailing arms. |
| `InpTrailDistance` | 100 | Distance behind price. |
| `InpTrailStep` | 20 | Minimum improvement before a modify is sent. |
| `InpUseBreakEven` | true | Enable break-even. |
| `InpBreakEvenAt` | 120 | Profit in points that triggers break-even. |
| `InpBreakEvenLock` | 20 | Points locked in at break-even. |

### 7. Protection
| Input | Default | Description |
|---|---|---|
| `InpMaxSpread` | 0 (off) | Block **new entries** above this spread, in points. Off by default so it can never silently block every entry — on gold, indices and crypto a "normal" spread is often 30–300 points. Set it once you know your symbol's typical spread. |
| `InpEquityStopPct` | 30.0 | Close all and halt at this equity drawdown %. `0` = off. |
| `InpMagic` | 20260903 | Magic number. Give each chart its own. |
| `InpSlippage` | 20 | Maximum deviation in points. |
| `InpDebug` | true | Log one line per bar saying exactly which gate stopped an entry. Leave on until the EA is trading, then turn it off. |

---

## 3b. If the EA opens no positions

`InpDebug` is on by default. Open **Toolbox → Experts** and you will get one line per bar naming
the gate that is shut, e.g.:

```
[ADR][EURUSD] indicator link OK — legDir=1 zone 1.08412..1.08533 origin 1.08290
[ADR][EURUSD] entry check: price 1.08610 has not reached the discount region (0.618 1.08533, origin 1.08290)
[ADR][EURUSD] entry check: the indicator reports no valid impulse leg yet
[ADR][EURUSD] entry check: all gates open — an entry should fire on the next tick
```

If you never see the `indicator link OK` line, the EA is not reading the indicator: check
`InpIndName`, and confirm `AdrenalineB1000.ex5` compiled without errors.

Other things worth checking first: **Algo Trading** enabled in the toolbar, the EA's own
*Allow Algo Trading* box ticked, and the market open.

---

## 4. On-chart status

The EA prints a compact block in the chart corner, refreshed once per second:

```
Adrenaline B1000 EA  |  EURUSD  PERIOD_M5
mode: BUY + SELL   spread: 8   running
leg: UP   zone: 1.08412 - 1.08533   [IN ZONE]
basket: BUY  3/5  vol 0.07  avg 1.08470
profit: 4.20 (32 pts)   trail: off
last arrow: BUY (score 6)
```

---

## 5. Suggested starting points

| Profile | TF | `InpLotStart` | `InpLotMult` | `InpMaxTrades` | `InpStepPoints` | `InpTakeProfit` |
|---|---|---|---|---|---|---|
| Conservative | M15 / H1 | 0.01 | 1.5 | 3 | 400 | 400 |
| Balanced | M5 / M15 | 0.01 | 2.0 | 4 | 250 | 300 |
| Aggressive | M1 / M5 | 0.01 | 3.0 | 5 | 150 | 200 |

Work out the worst case before going live. With base 0.01, multiplier 3.0 and 5 rungs the ladder
is 0.01 + 0.03 + 0.09 + 0.27 + 0.81 = **1.21 lots**, and the full ladder is spread across
150 + 300 + 450 + 600 = 1 500 points of adverse movement. Check that your balance survives that on
your symbol, then set `InpEquityStopPct` below the point where it would not.

---

## 6. Strategy Tester

* Model: **Every tick based on real ticks** — the martingale adds and the trailing stop are both
  intra-bar, so 1-minute OHLC will flatter the results.
* Test on a **hedging** demo server to see the individual rungs.
* Deposit and leverage matter far more than usual here: re-run the same settings at your real
  deposit before trusting a curve.
* Optimise `InpStepPoints`, `InpTakeProfit` and `InpLotMult` together — they are not independent.
* The EA's status `Comment` and all logging are skipped during optimization.

---

## 7. Risk warning

Martingale increases exposure while a position is losing. A long enough adverse move exhausts any
account, whatever the settings. `InpEquityStopPct` bounds the damage but does not remove it. Run
this on a demo account for a full market cycle before considering anything else, and size
`InpLotStart` for the whole ladder, never for the first position.

---

## 8. Ideas for the next version

* Partial close of the largest rung when the basket reaches break-even.
* Hedge-lock instead of a hard equity stop, unwinding the basket as price returns.
* Risk-percent based `InpLotStart` derived from the leg's invalidation level.
* Reading the 1.272 / 1.618 extension buffers as dynamic targets instead of a fixed point TP.
