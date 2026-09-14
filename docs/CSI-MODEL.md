# CSI-Omega — candle-scored leg strength and reversal model

A formal, computable specification of the "CSI" method, implemented in
`mt5/CSI_Omega.mq5`.

The source material was a set of annotated XAUUSD M15 charts plus a pipeline
diagram. This document records what those charts established, what they left
under-specified, and the formula adopted in place of the gaps.

```
Candle pattern -> Vi -> CNSn -> (CS, SP, NP) -> CSI -> CD
               -> Continuation / Reversal -> RP -> model transition / reset
```

---

## 1. What the source material established

| Claim | Evidence | Status |
|---|---|---|
| Every qualifying candle carries a **pre-assigned score, not a unit count** | "ทุกแท่งที่รับมีคะแนนที่กำหนดไว้แล้ว ไม่ใช่จำนวน" | confirmed |
| Scores accumulate across one swing leg into a total (`CNS`) | up leg `2 -> 32`, down leg `3 -> 13` | confirmed |
| Counting anchors at a swing pivot and terminates at the opposing pivot | "จุดที่เริ่มนับ" marked at the swing low | confirmed |
| `CSI = 0.5a + 0.3b + 0.2c` | `0.5(75)+0.3(70)+0.2(80) = 74.5`; `0.5(70)+0.3(60)+0.2(75) = 68` | confirmed, both arithmetically exact |
| Two consecutive legs are fused into one figure | `F = sqrt(AB) ((A+B)/2 - |A-B|^2/4)` with `A=74.5, B=68` | stated, see §5 |
| The fused verdict resolved **down** | price fell `4,443 -> 4,345` after the pair | confirmed by the charts |

### Net score per bar is consistent across both legs

Bar counts read off the charts (up leg ~68 bars, down leg ~24 bars) give a net
score of **0.47** and **0.54** per bar. Two independent legs landing that close
together is strong evidence that `CNS` is a **signed** accumulation — counter-
direction candles subtract. A purely additive count over 68 bars could not
total 32.

This is the single most useful inference in the whole set, and it is what
`CandleValue()` implements.

---

## 2. What was under-specified

Two gaps block a faithful reimplementation. Both are filled with original
definitions, flagged here so they can be replaced if the original rules surface.

### Gap 1 — the `Vi` table was never shown

No candle-to-score mapping appears anywhere in the material. §3 defines one.

### Gap 2 — nothing connects `CNS` to the `(CS, SP, NP)` triplet

The two published triplets are `(75, 70, 80)` from `CNS = 32` and
`(70, 60, 75)` from `CNS = 13`.

No function of `CNS` alone reproduces both. Two observations fit any
two-parameter family — a straight line through them gives
`CS = 66.6 + 0.263·CNS`, which is arithmetically valid and behaviourally
absurd (a leg with zero net score would still read `CS = 67`). A saturating
map calibrated to `32 -> 75` returns `43`, not `70`, for `CNS = 13`.

Every published component is a multiple of 5. The triplets are therefore
**discretionary or bucketed inputs, not derived quantities** — the pipeline has
a break between `CNS` and `CS/SP/NP`. §4 closes it with three measurable
quantities.

### A third point: the published arithmetic does not close

```
(A+B)/2      = 142.5/2 = 71.25
|A-B|^2 / 4  = 6.5^2/4 = 10.5625
71.25 - 10.5625 = 60.6875
```

The reference calculator screen used **61.038**, giving `4,344.43` where the
stated formula gives `4,319.49`. A 0.35 discrepancy in the bracket, unexplained
by any shown step.

---

## 3. Stage 1 — `Vi`, the per-candle value

For candle `i` in a leg of direction `d` (`+1` up, `-1` down), with
`range = H - L` and `bodyRatio = |C - O| / range`:

| Class | Condition | Magnitude |
|---|---|---|
| Marubozu | `bodyRatio >= 0.80` | 4 |
| Strong body | `>= 0.60` | 3 |
| Standard body | `>= 0.40` | 2 |
| Weak body | `>= 0.20` | 1 |
| Doji / indecision | `< 0.20` | 0 |

The magnitude is **signed by agreement with the leg**: a candle closing with
the leg adds it, a candle closing against the leg subtracts it, a doji
contributes nothing. A candle whose wick against the leg direction exceeds 50%
of its range is a rejection in the leg's favour and adds a further `+1`.

Calibration: this yields roughly `+0.4` to `+0.6` net per bar on a healthy
trending leg, which is exactly the rate both reference legs exhibit.

Every threshold and score is an input, so the table can be replaced wholesale
without touching the code.

## 4. Stages 2–3 — `CNS`, then `CS`, `SP`, `NP`

`CNS = Σ Vi` over the leg, `N` = bars in the leg, `ΔP` = close-to-close
displacement, `path = Σ |Ci - Ci-1|`.

**`CS` — candle strength.** Net score per bar through a bounded sigmoid, so a
long limp leg cannot out-score a short decisive one on bar count alone:

```
CS = 100 / (1 + exp(-α (CNS/N - μ)))          α = 3.0, μ = 0
```

**`SP` — structure purity.** Kaufman efficiency ratio, scaled so a clean leg
reads 100:

```
ER = |ΔP| / path
SP = 100 · min(1, ER / ER_ref)                ER_ref = 0.60
```

**`NP` — net projection.** Displacement in ATR units, saturating, so the score
is comparable across symbols and volatility regimes:

```
NP = 100 (1 - exp(-|ΔP| / (k · ATR)))         k = 8
```

**`CSI = 0.5·CS + 0.3·SP + 0.2·NP`** — the weights are the source material's,
used unchanged. All three components are `0..100`, so `CSI` is too.

### Calibration against the reference legs

Using values read off the charts (up leg: 68 bars, `ΔP = 61`, `ER ≈ 0.28`;
down leg: 24 bars, `ΔP = -55`, `ER ≈ 0.45`), swept across plausible ATR:

| ATR | up-leg CSI | down-leg CSI | B/A | CD | verdict |
|---|---|---|---|---|---|
| 3.0 | 72.6 | 82.3 | 1.133 | 77.0 | REVERSAL DOWN |
| 4.0 | 71.2 | 80.7 | 1.133 | 75.5 | REVERSAL DOWN |
| 5.0 | 69.8 | 79.2 | 1.134 | 74.1 | REVERSAL DOWN |
| — | *74.5 (author)* | *68.0 (author)* | *0.913* | *71.0* | *REVERSAL DOWN* |

CSI lands in the same 70–83 band as the published figures from chart-derived
quantities only, and **the verdict is the one price delivered** — gold fell
`4,443 -> 4,345` immediately after. The verdict is stable across the whole ATR
sweep, so it does not depend on the eyeballed inputs.

Note the two models disagree on *which* leg is stronger while agreeing on the
outcome. Under CSI-Omega the counter-leg scores higher outright (`B/A > 1`);
under the published figures it scores lower and only a near-match rule rescues
the call. That makes CSI-Omega's verdict the better-supported of the two.

## 5. Stage 4 — `CD`, the two-leg fusion

The published form is unusable as written:

```
F = sqrt(AB) ((A+B)/2 - |A-B|^2/4)
```

The penalty term is **quadratic in an absolute gap** while the magnitude term
is linear, so `F` turns negative once two legs differ by about 17 points and
then diverges without bound:

| A | B | published `F` | `CD` |
|---|---|---|---|
| 74.5 | 68 | 4,319 | 71.0 |
| 80 | 65 | 1,172 | 71.3 |
| 80 | 60 | **-2,079** | 67.9 |
| 85 | 50 | **-15,565** | 60.8 |
| 100 | 10 | **-62,297** | 10.5 |

A strongly one-sided pair — precisely the case a structure model should score
*clearly* — produces a large negative number on an otherwise `0..100` scale.

CSI-Omega keeps the intent (geometric mean, so both legs must be strong;
quadratic divergence penalty) and takes the penalty on the **relative** gap,
which bounds the result to `0..100` for every input pair:

```
CD = sqrt(A·B) · (1 - (|A-B| / (A+B))^2)
```

At `A = 74.5, B = 68` this gives `CD = 71.0` — the same neighbourhood as the
published intent, without the pathology.

## 6. Stages 5–7 — verdict, `RP`, reset

With `A` = the previous leg's CSI, `B` = the newly closed opposing leg's CSI,
and `ρ = B/A`:

| Condition | Verdict |
|---|---|
| `ρ >= 1.10` | **Reversal** in leg `B`'s direction — the counter-leg outscored the impulse it answered |
| `ρ <= 0.75` | **Continuation** of leg `A`'s direction — the counter-leg was only a pullback |
| otherwise | Neutral |
| `CD < 45` | forced Neutral regardless — both legs too weak to read |

### Why these thresholds and not the source material's

The source material implies `ρ >= 0.85` for reversal and `ρ <= 0.55` for
continuation. Those do not survive contact with this scale. Measured over 371
legs of synthetic M15 data, `ρ` is tightly centred on parity:

| min | p10 | p25 | median | p75 | p90 | max |
|---|---|---|---|---|---|---|
| 0.00 | 0.68 | 0.86 | **1.00** | 1.13 | 1.45 | 3.77 |

Consecutive legs score similarly because `CS`, `SP` and `NP` are all bounded
and normalised. A `0.85` floor therefore labels most of the chart a reversal:

| thresholds | reversals | continuations | neutral |
|---|---|---|---|
| 0.85 / 0.55 (source) | **77%** | 4% | 19% |
| 1.00 / 0.70 | 50% | 11% | 39% |
| **1.10 / 0.75 (adopted)** | **28%** | **14%** | **57%** |
| 1.20 / 0.80 | 19% | 19% | 62% |

At the source's thresholds the model flips direction on nearly every swing,
which is not a signal. Recentring on parity — the counter-leg must *outscore*
the impulse, not merely approach it — makes the verdict selective while
keeping the one labelled example correct: the reference pair scores `ρ = 1.133`
under this model (§4), still a reversal at `1.10`.

This is a genuine departure from the source, not a transcription. It is forced
by the sub-score definitions in §4: a different `CS/SP/NP` would put `ρ` on a
different scale and would need its own thresholds.

### `RP`, levels and invalidation

`RP` is the pivot that terminated leg `B`. Which level invalidates the verdict
depends on the verdict, not on the trade direction:

| Verdict | Invalidated by |
|---|---|
| Reversal | the leg's **origin** — price returning there means the counter-leg never took control |
| Continuation | the **pivot** the leg just failed at |

Using the pivot for both is wrong and silently so. Confirmation only arrives
*after* price has retraced away from the pivot, so a long's stop taken from
the pivot lands **above** its own entry. Measured on 267 synthetic signals
before the rule was corrected, **266 had the stop on the wrong side of entry**
and every one resolved as an immediate loss. After the fix: 0 of 106.

A stop is additionally floored at `0.75 ATR` from entry. A structurally
correct stop can still sit inside the noise when the pivot is near the
confirmation bar; the floor only ever widens it, never tightens it.

**Reset.** Each confirmed pivot rolls the window (`A <- B`), zeroes the
accumulator and starts a new leg. Nothing carries across a transition.

## 7. Known limits

- **A leg is scored only on confirmation.** The terminating swing is confirmed
  by an ATR-scaled retracement, which lags the actual pivot. This is inherent
  to swing scoring, not an implementation shortcut. Every bar is fed to the
  engine exactly once and only after it closes, so values are never revised
  and the plot does not repaint.
- **No edge has been demonstrated.** The synthetic runs above verify
  *mechanics* — that stops land on the correct side, that verdicts are
  selective, that `CSI` and `CD` stay bounded. They are generated data with
  trend regimes built in, so the hit rate they produce says nothing about live
  performance and must not be read as one.
- **Calibrated on one labelled example.** The reference material contains a
  single leg pair with a known outcome. The defaults are principled rather
  than fitted. Run the Strategy Tester across several hundred legs on real
  data before trading it.
- **Gaps 1 and 2 are filled with original definitions**, and §6's thresholds
  are a third departure. If the original `Vi` table and `CS/SP/NP` rules
  surface, they belong in §3 and §4, and both the §4 calibration and the §6
  thresholds must be re-derived.
