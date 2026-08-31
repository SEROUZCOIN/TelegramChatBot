# Fibonacci retracement

A working reference built from the mathematics, the primary literature, the
public backtests, and the long-running arguments on the trading forums. It is
written to be *usable* — by a trader drawing levels, and by an engineer
automating them — which means it says plainly where the tool has no edge as
well as where it does.

> **Educational material.** Nothing here is a recommendation to trade, and no
> level, ratio, or win rate on this page should be presented to a subscriber as
> a prediction. See [`docs/COMPLIANCE.md`](../COMPLIANCE.md) — the platform sells
> analysis and education, not outcomes.

---

## The one-paragraph version

A Fibonacci retracement is a ruler. You anchor it across a price leg you believe
was impulsive, and it divides that leg at fixed fractions — 23.6%, 38.2%, 50%,
61.8%, 78.6%. Traders watch those fractions for pullback entries. The evidence
that price turns at Fibonacci fractions more often than at arbitrary fractions is
weak to absent: the published academic tests and the large-sample backtests
mostly find nothing. What the ruler *does* give you is an objective, repeatable
way to choose **where in a pullback to enter**, which fixes your risk-to-reward
before you take the trade. As [the arithmetic below](#the-identity-that-explains-the-whole-argument)
shows, that trade-off is priced exactly at par — the ladder itself is
edge-neutral — so every bit of profitability has to come from something *outside*
the ladder: context, confluence, the entry trigger, and cost control. Traders who
say "Fibonacci works" and traders who say "Fibonacci is nonsense" are usually
both right, about different halves of that sentence.

---

## 1. Where the numbers come from

### The sequence and the ratio

The Fibonacci sequence adds each term to the one before it:

```
0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, …
```

Divide any term by the next and the quotient converges on **0.6180339887…**;
divide by the previous and you get **1.6180339887…** — the golden ratio, φ.
`144/233 = 0.61802`, `233/144 = 1.61805`. Convergence is quick: it is already
accurate to three decimals by the eighth term.

φ has two properties that matter here, and they are the reason the ladder is
self-similar rather than an arbitrary list:

```
φ² = φ + 1          →   1.618² = 2.618
1/φ = φ − 1         →   1/1.618 = 0.618
φ = (1 + √5) / 2
```

Because multiplying by φ is the same as adding one, ratios of φ nest inside each
other. Any level in the ladder is a power or root of any other.

### Every level, derived

| Level | Where it comes from | Exact-ish value |
|---|---|---|
| **23.6%** | term ÷ term three places later, `= 0.618³` | 0.2360 |
| **38.2%** | term ÷ term two places later, `= 0.618²` | 0.3820 |
| **50%** | **not Fibonacci at all** — Dow and Gann | 0.5000 |
| **61.8%** | term ÷ next term, `= 1/φ` | 0.6180 |
| **70.5%** | **not Fibonacci** — midpoint of the ICT 62–79 band | 0.7050 |
| **78.6%** | `√0.618` | 0.7861 |
| **88.6%** | `√0.786` = `⁴√0.618` | 0.8857 |
| **127.2%** | `√1.618` | 1.2720 |
| **161.8%** | `φ` | 1.6180 |
| **200%** | not Fibonacci — a doubling | 2.0000 |
| **261.8%** | `φ²` | 2.6180 |
| **423.6%** | `φ³` | 4.2360 |

Two entries on that list are worth pausing on, because they are the ones that
quietly undermine the mystique:

- **50% is not a Fibonacci number.** It is on your chart because Charles Dow
  wrote in the late 1800s that markets tend to retrace roughly a third to
  two-thirds of a move, and because W.D. Gann built a method around the halfway
  point in the early 1900s — both predating Fibonacci's arrival in market
  analysis. It survives on the ladder purely because it is useful. That it is
  *the* level most traders watch, and that it isn't Fibonacci, is the tell.
- **78.6% and 88.6% are square roots, not ratios.** They are not in the sequence
  and are not quotients of it. They were added later because practitioners
  (notably the harmonic-pattern school) found deep retracements clustering there.

So of the seven lines on a default retracement tool, three (50%, 78.6%, and the
88.6% many traders add) are not Fibonacci ratios. The ladder is a practitioners'
toolkit with a Fibonacci label on the box.

> **The sequence is also older than Fibonacci.** Leonardo of Pisa introduced it
> to Europe in *Liber Abaci* (1202) via the rabbit-breeding problem, but it
> appears centuries earlier in Indian prosody — Pingala, then Virahanka and
> Hemachandra — counting the arrangements of long and short syllables.

---

## 2. How it got into trading

| When | Who | What they added |
|---|---|---|
| Late 1800s | **Charles Dow** | Observed retracements of roughly ⅓ to ⅔; the origin of "about half" |
| Early 1900s | **W.D. Gann** | Built a method on the 50% retracement specifically |
| 1930s | **H.M. Gartley** | *Profits in the Stock Market* (1935) — the five-point "222" pattern, **without** Fibonacci ratios |
| 1930s–40s | **R.N. Elliott** | The Wave Principle; *Nature's Law* (1946) grounds wave relationships explicitly in Fibonacci |
| 1978 | **Frost & Prechter** | *Elliott Wave Principle* — codified the wave-to-wave Fibonacci guidelines still used today |
| 1990s | **Bryce Gilmore** | The Butterfly pattern; heavy use of 0.786 |
| 1997 | **Larry Pesavento** | *Fibonacci Ratios with Pattern Recognition* — retrofitted Fibonacci ratios onto Gartley's pattern |
| 1999–2000s | **Scott Carney** | *Harmonic Trading* — Bat (2001), Crab, Shark, 5-0; formal ratio rules and risk management |
| 2008 | **Constance Brown** | *Fibonacci Analysis* — a corrective book, largely about how the tool is misapplied |
| 2010s– | **ICT / smart-money** | Optimal Trade Entry: the 62–79% band, "sweet spot" 70.5% |
| 2017– | **Crypto retail** | The "golden pocket" — popularised on TradingView and crypto Twitter |

Note the direction of travel. The ratios did not arrive from mathematics and get
validated by markets; a retracement heuristic already existed (Dow, Gann), and
Fibonacci ratios were fitted to it afterwards, then extended with non-Fibonacci
roots when the original ratios did not cover what practitioners were seeing.

---

## 3. Drawing it correctly

Most arguments about whether Fibonacci "works" are actually arguments about
anchoring. Get this part disciplined and the rest of the debate narrows sharply.

### The anchors

- **Anchor across one completed impulse leg** — a directional move that visibly
  broke structure, not a drift and not a range. If you cannot say in one sentence
  why that leg was impulsive, you do not have an anchor.
- **Uptrend:** drag from the swing low (0%) to the swing high (100%). Retracement
  levels then sit *below* the high, as potential support.
- **Downtrend:** drag from the swing high to the swing low. Levels sit above the
  low, as potential resistance.
- Platforms differ on which end reads 0%. Ignore the labels; the levels are
  identical either way.

### Wicks or bodies

Both camps have adherents. The rule everyone actually agrees on:

> **Pick one and never mix.** Anchoring 0% to a body and 100% to a wick produces
> levels that are simply wrong — they measure a leg that never happened.

Default to **wick-to-wick**: it captures the full range that traded, it is
unambiguous, and it is what an automated pivot detector will find. Body-to-body
has a defensible rationale (ignore the stop-run tail, measure where the market
accepted price) but requires you to apply it consistently across every chart
forever, and most traders don't.

### Defining a swing objectively

The forum answer — "the obvious high" — is useless to a beginner and impossible
to automate. Use a mechanical definition:

- **BabyPips-style:** a swing high is a candle with at least two lower highs on
  each side; a swing low, two higher lows on each side.
- **Pivot / fractal, generalised:** bar *i* is a swing high if `high[i]` is the
  maximum of the window `[i−N, i+N]`. `N` is the whole game — small `N` marks
  every wiggle, large `N` keeps only major turns.
- **Add a size filter:** require the leg into the pivot to be at least *k* × ATR.
  A pivot formed by a large impulse is structurally different from a shallow
  wiggle that happens to satisfy the shape test.

The cost of an objective definition is **lag**: a swing high with `N = 5` is not
knowable until five bars after it printed. That is not a flaw to engineer away —
see [§8](#8-automating-it-without-fooling-yourself). It is the price of a rule
that a backtest can honestly evaluate.

### Log or linear

Match the Fibonacci tool's scale to the chart's scale. On a log chart, equal
vertical distance means equal *percentage* change; a linear Fib drawn over a log
chart (or vice versa) puts the lines in the wrong places. This is invisible on a
one-day 30-pip range and enormous on a multi-year crypto chart. **Rule:** short
horizons and low-volatility instruments, linear; multi-year or exponential
moves, log — and set both the chart and the tool the same way.

### Which timeframe

Higher timeframes produce more reliable levels, for a reason that is not
mystical: they are drawn from legs that more participants can see and agree on.
Daily and 4-hour levels are watched; 5-minute levels are noise dressed as
structure. If you trade intraday, take the *bias and the levels* from the higher
timeframe and use the lower timeframe only for the trigger.

---

## 4. What the evidence actually says

This is the section most Fibonacci guides skip. It should change how you use the
tool, not whether you use it.

### Academic testing

- **"Automatic identification and evaluation of Fibonacci retracements"**
  (*Expert Systems with Applications*, 2021) tested retracements systematically
  across three equity markets. Logistic regression slopes were **statistically
  insignificant**; the probability of price reacting at a Fibonacci zone was
  **indistinguishable from a non-Fibonacci zone**; and a trading rule built on
  the levels **underperformed buy-and-hold**.
- A **survey of retracement distributions on trend data** (arXiv 1605.03559)
  found retracement depths follow a **continuous distribution** — refining the
  histogram does not reveal spikes at 38.2, 50, or 61.8. There is no lump at the
  golden ratio.
- A widely cited **City University** analysis reported that the frequency with
  which peak-to-trough ratios landed near a Fibonacci ratio was **lower than
  chance would predict**.

### Large-sample backtests

- A backtest across **102 stocks and indices** found the retracement failed to
  mark a turning point **63% of the time**, and that the 38.2/50/61.8 levels
  were **no more likely to produce a turn than any other level**.
- **Trading Rush's 100-trade test** is the most quoted retail experiment, and its
  numbers are worth memorising because they are so flat. Where price reacted,
  having filtered for trend with a 200-period moving average:

  | Level | Reactions |
  |---|---|
  | 23.6% | 6% |
  | 38.2% | 18% |
  | 50.0% | 14% |
  | 61.8% | **15%** |
  | 78.6% | 14% |
  | Reached 100% or blew through everything | **33%** |

  Two readings. First, 38.2 through 78.6 are within a few points of each other —
  the golden ratio is not special within its own ladder. Second, **the single
  most common outcome, by a wide margin, is no reaction at all.** A third of the
  time the pullback ate the whole leg. Any method built on these levels must
  survive that being the base case.

### The forum arguments, fairly stated

**For the tool.** Traders who use it profitably describe it as a location filter,
not a signal: it stops them chasing extended price, it forces a defined
invalidation point, and it makes entries mechanical once a swing is chosen.
"Only take the trade after a 50% retracement, in the trend direction" is a
complete, testable rule, and that discipline is worth something regardless of
whether the specific fraction is magic.

**Against the tool.** The sharpest criticism on Forex Factory is that 38.2% and
61.8% merely mean "a bit of a pullback" and "most of the way back" — you can read
that from the chart without a tool, and dressing it in a ratio adds false
precision. A second line of attack: the drawing is subjective, there are no firm
rules, so any level can be justified after the fact. A third, aimed squarely at
the self-fulfilling-prophecy defence: in FX, *the participants who move price
don't trade off retail Fibonacci levels, and the participants who do lack the
size to move price.*

**The self-fulfilling prophecy, examined.** The standard defence is that levels
work because enough people watch them. It is a real mechanism — order
concentration is how any horizontal level works — but it carries a condition
that its advocates rarely state:

> A self-fulfilling level requires participants to agree not just on the
> *ratio* but on the *anchors*. The ratio is universal; the anchors are not.

This resolves most of the argument. The mechanism is strongest exactly where the
anchor is unambiguous — one obvious, recent, large swing on the daily chart of a
heavily traded instrument, where thousands of traders will draw the identical
leg. It is weakest on a 5-minute chart, where no two traders pick the same swing
and there is no shared level to defend. It also predicts that Fibonacci works
better on liquid, widely-watched instruments than on thin ones — which is what
practitioners report, and it needs no appeal to natural harmony to explain.

### Where that leaves you

Nothing above says *don't use it*. It says: **the levels are not a forecast, and
any strategy whose edge is supposed to come from the ratio itself is built on
sand.** Use the ladder for what it demonstrably is — a consistent, communicable
way to locate an entry within a pullback and to define where you are wrong.

---

## The identity that explains the whole argument

Here is the cleanest way to see why the ladder alone cannot make you money — and
why it is nonetheless the right tool for the job it actually does.

Take a long. Leg low `L`, leg high `H`. Enter on a retracement of fraction `r`,
stop at the leg origin `L`, target a retest of `H`:

```
entry   E = H − r(H − L)
risk    E − L = (H − L)(1 − r)
reward  H − E = r(H − L)

R  =  r / (1 − r)
break-even win rate  =  1 / (1 + R)  =  1 − r
```

The `(H − L)` cancels, so this holds on any instrument, any timeframe, any leg
size:

| Enter at | Reward:risk | Win rate needed to break even |
|---|---|---|
| 38.2% | 0.62 : 1 | **61.8%** |
| 50.0% | 1.00 : 1 | **50.0%** |
| 61.8% | 1.62 : 1 | **38.2%** |
| 70.5% | 2.39 : 1 | **29.5%** |
| 78.6% | 3.67 : 1 | **21.4%** |
| 88.6% | 7.77 : 1 | **11.4%** |

Read that table carefully. **The break-even win rate is exactly `1 − r`.** Enter
deeper and the payoff improves by precisely as much as the probability of the
trend surviving the deeper pullback must worsen for you to stay level. The
geometry is priced at par. It cannot manufacture an edge, and it cannot destroy
one either.

Three consequences follow, and they are the practical heart of this document:

1. **A Fibonacci entry is profitable only if the level holds more often than
   `1 − r`.** That is the empirical claim to test — the only one that matters —
   and it is precisely the claim the studies in §4 fail to support for the ratio
   in isolation. Your job is to find the *conditions* under which it is true
   (trend, structure, confluence, session, instrument), not to find a better
   number.
2. **Costs make par a loss.** Spread, commission, slippage, and swap all come out
   of the reward side, and the stop needs a buffer beyond `L` that comes out of
   the risk side. Trading the ladder with no edge source is not break-even; it is
   a slow, arithmetically guaranteed bleed.
3. **This is why the deep-entry schools exist.** ICT's 62–79% Optimal Trade Entry
   band is not a claim that price reverses at 70.5%. It is a claim that *if* your
   read of the trend is right, entering deep is where the reward:risk is worth
   taking. The band is a risk-placement argument wearing Fibonacci clothing —
   which is also why it is always paired with strict preconditions (liquidity
   taken, structure shifted) rather than used on its own.

The identity assumes a full retest of `H`; in practice price often stalls short,
which pushes every row slightly worse. Treat the table as an optimistic ceiling.

---

## 5. The schools of practice

Different traditions use the same ladder for genuinely different purposes. Mixing
their rules is a common source of confusion.

### Elliott Wave

Fibonacci relationships as *wave guidelines*, never as standalone signals:

- **Wave 2** typically retraces **50–61.8%** of wave 1, often deeper (78.6%);
  a shallow wave 2 is unusual.
- **Wave 4** typically retraces **23.6–38.2%** of wave 3 — much shallower, and
  by rule must not enter wave 1's territory in an impulse.
- **Wave 3** commonly extends to **161.8%** of wave 1; wave 5 often relates to
  wave 1 by 0.618 or 1.0.
- The alternation between a deep wave 2 and a shallow wave 4 is the most
  practically useful piece of the framework, whatever you think of the rest.

Frost & Prechter are explicit that these are **guidelines, not rules** —
expected zones, not predictions.

### Harmonic patterns

The most rule-bound use of Fibonacci: a pattern is only valid if its legs hit
specified ratios inside a tolerance.

| Pattern | Defining ratios |
|---|---|
| **Gartley** | B retraces 0.618 of XA; D retraces **0.786** of XA |
| **Bat** | B retraces 0.382–0.50 of XA; D at **0.886** of XA; CD extends 1.618–2.618 of BC |
| **Butterfly** | B at 0.786 of XA; D **extends beyond X** (1.272–1.618 of XA) |
| **Crab** | D at the **1.618** extension of XA — the deepest of the family |

The virtue is falsifiability: the ratios either hit within tolerance or the
pattern does not exist, which makes harmonics testable in a way that discretionary
Fibonacci is not. The vice is the tolerance band itself — widen it and you can
find a pattern anywhere.

### ICT / smart money — Optimal Trade Entry

The **62–79% band**, midpoint **70.5%**, entered only after a specific sequence:
liquidity taken → displacement → market-structure shift → retracement into the
band, ideally overlapping an order block or fair-value gap. The Fibonacci band is
the *last* filter in the checklist, not the setup. Used without the preconditions
it is simply a deep limit order into a pullback, with the risk profile the table
above describes.

### The crypto "golden pocket"

The band immediately below 61.8%. **Be aware the definition is not agreed:**
some traders mean **0.618–0.65** (a tight zone), others mean **0.618–0.786** (a
wide one, effectively the OTE band). They are different trades with different
risk. When someone quotes a golden-pocket win rate, find out which one they mean
before believing the number.

### Classical confluence trading

The mainstream approach, and the one that survives contact with the evidence
best: Fibonacci as **one vote among several**. A level counts only when it
overlaps something independently meaningful — a prior swing high or low, a
well-tested horizontal, a 50/200 EMA, a volume shelf, a round number, a session
high. The Fibonacci line contributes precision to a level you would have had
reason to watch anyway.

---

## 6. A working method

A checklist you can actually follow, and — importantly — one you can backtest
without ambiguity. The order matters: Fibonacci enters at step 4, not step 1.

**1. Establish bias on the higher timeframe.** One timeframe up from the one you
will execute on, at minimum. If you cannot state the trend in a sentence, there
is no setup. Counter-trend retracement trades are a different, harder game.

**2. Find a completed impulse leg.** It must have broken a prior swing point in
the trend direction. A leg that merely drifted is not an impulse and the ladder
drawn across it means nothing.

**3. Anchor the tool.** Wick to wick. Scale matched. Do not adjust it afterwards
to make a level fit — that single habit invalidates more Fibonacci trading than
any flaw in the ratios.

**4. Require confluence before the level counts.** At least **two independent,
non-Fibonacci** factors in the zone: prior structure, a moving average, a volume
node, a session level, an order block, a round number. Two Fibonacci levels from
two different legs landing together is *one* factor, not two — they are not
independent. Multi-timeframe clusters, where a daily level and a 4-hour level
overlap in a tight band, are the strongest version of this.

**5. Wait for a trigger. Do not enter on touch.** The zone tells you *where*;
something else must tell you *when*. A rejection candle closing back out of the
zone, a lower-timeframe structure shift, momentum divergence — pick one, define
it precisely, use it every time. This is the step that separates the traders who
report Fibonacci working from those who report it failing, and it is the step
most often skipped.

**6. Place the stop by structure, not by the level.** Beyond the leg origin, or
beyond the 78.6/88.6, plus an ATR-scaled buffer. Never tuck it immediately behind
a Fibonacci line — that line is visible to everyone, which is exactly why it gets
swept. A tight stop is not a small risk; it is a high probability of being
stopped out of a trade that would have worked.

**7. Size the position from the stop distance.** Fixed fractional risk. The stop
comes from structure and the size follows from the stop — never the reverse.

**8. Set targets before entry.** First the prior swing extreme, then the 1.272 and
1.618 extensions. Scale out or move to break-even at a pre-decided point.

**9. Define invalidation.** A *close* beyond the leg origin ends the setup. Not a
wick, not "it might come back" — a close. Write it down before you enter.

**10. Log the trade with its anchors.** Record the exact swing points used. When
you review, you will find that most losses trace back to step 2 or step 3, not to
the level being wrong.

### The complement: extensions and targets

Retracements find entries; extensions find exits. The distinction between the
three tools trips up nearly everyone:

- **Retracement** — two points. Divides the leg you drew.
- **Extension** — three points (A, B, C). Projects a multiple of A→B from **B**,
  and reads the levels beyond the leg.
- **Projection / expansion** — three points. Projects the length of A→B from
  **C**, the end of the retracement.

Vendors use these names inconsistently — Forex Factory has an entire thread on
exactly this — so check what your platform's tool measures before trusting a
number it prints. **1.618** is the most watched extension target, then **1.272**;
**2.618** for a strongly extended move. In an Elliott frame, a third wave running
to 161.8% of the first is the canonical example.

---

## 7. The other Fibonacci tools

Honest assessment, since every platform ships them:

| Tool | What it draws | Verdict |
|---|---|---|
| **Fans** | Diagonal lines at Fibonacci angles from a pivot | Occasionally useful in a steady trend where horizontals give little guidance. Sensitive to the anchor; the angle depends on your chart's aspect ratio, which is a real conceptual problem. |
| **Arcs** | Semicircles from a pivot | Combines price and time in a way that depends entirely on chart scaling. Hard to test, rarely used. |
| **Time zones** | Vertical lines at Fibonacci bar counts | Attractive in retrospect. The bar counts grow so fast that later lines are dozens of bars apart, so "a turn near the line" becomes unfalsifiable. |
| **Channels** | Parallel channel divided by Fibonacci ratios | Essentially a channel with extra lines. The channel is doing the work. |

The consensus across forums and educators is that these are **rarely used except
inside systems built specifically around them**. Retracements and extensions
carry nearly all the practical value. If you are learning, learn those two
properly and ignore the rest until you have a reason not to.

---

## 8. Automating it without fooling yourself

If you plan to compute Fibonacci setups programmatically — for a scanner, an
indicator, or a signal feed — this section matters more than everything above it,
because the failure modes are silent and they all flatter the strategy.

### The ZigZag trap

ZigZag is the standard swing detector and the standard way to get a fictional
backtest. **Its final leg is provisional**: it extends and redraws as new
extremes print, so the levels it produces today are not the levels it showed at
the time. Reports on the MQL5 forum put the repaint rate on the last leg at
60–70%. A backtest that reads ZigZag output bar by bar is reading information
that did not exist when the trade would have been placed. The result is a
beautiful equity curve that cannot be traded.

This is not a bug to be patched. It is inherent: **a swing cannot be confirmed
until the bars after it have closed.**

### A non-repainting formulation

```
swing_high(i)  ⇔  high[i] == max(high[i−N … i+N])
confirmed at   :  bar i + N          # never earlier
```

Accept the `N`-bar lag as the cost of an honest signal, then add structure filters
on top:

- The leg into the pivot must be ≥ `k × ATR(period)` — filters shallow wiggles.
- The leg must **break the prior swing** in the trend direction to count as an
  impulse.
- Anchors, once confirmed, are **immutable**. A new leg creates a new setup; it
  never edits an old one.

That last rule is worth stating in code, not just in comments. It is the same
discipline this repository already applies to signal status — see
[`packages/shared/src/signal-state.ts`](../../packages/shared/src/signal-state.ts),
where status is a fold over an append-only ledger rather than a mutable field,
precisely so that what a subscriber saw cannot be quietly rewritten. A Fibonacci
setup deserves identical treatment: **append a new setup, never mutate a
published one.** A level that silently moves after publication is the same
integrity failure as a win rate that improves after the fact.

### A setup as a state machine

```
IDLE
  └─ pivot confirmed (N bars closed) and leg ≥ k·ATR and structure broken
       → LEG_CONFIRMED        (anchors frozen; levels computed once)
            └─ price trades into [r_min, r_max]
                 → ARMED
                      ├─ trigger bar closes            → TRIGGERED
                      ├─ close beyond leg origin       → INVALIDATED
                      └─ m bars with no trigger        → EXPIRED
```

Every transition is decided by a **closed bar**. No transition may consult a bar
later than the one being processed. If you can state that invariant and enforce
it in one place, most look-ahead bugs become impossible rather than merely
unlikely.

### Backtest hygiene

- **Replay bar by bar.** Never let the strategy see a bar it would not have had.
  Manual chart study has the same requirement — advance the chart one bar at a
  time and do not scroll right.
- **Count the non-events.** Setups where price never reached the zone are part of
  the sample. Dropping them is the most common way a Fibonacci backtest
  accidentally reports a 70% win rate.
- **Charge full costs.** Spread, commission, slippage, swap. The geometry is at
  par before costs, so a backtest that omits them is not measuring an edge — it
  is measuring the sign of the fees.
- **Test the actual claim.** Not "is this profitable" but **"does the level hold
  more often than `1 − r`?"** — with a control. Run the identical logic on
  arbitrary fractions (0.44, 0.57, 0.71). If the Fibonacci fractions do not
  separate from the controls, your edge is in the trend filter and the trigger,
  which is useful to know and changes what you should optimise.
- **Cover regimes.** Five years or more, including strong trends, chop, and at
  least one high-volatility break. Fibonacci strategies are trend-dependent and
  will look excellent over a trending sample alone.
- **Do not co-optimise** `N`, `k`, `r`, and the trigger on one dataset. Walk
  forward, or you are fitting the sample.
- **Instrument caveat.** Synthetic indices with engineered spike behaviour
  (Boom/Crash and similar) have retracement statistics that have nothing to do
  with FX or equities. Never carry parameters across instrument classes without
  re-testing.

---

## 9. Cheat sheet

```
φ = 1.6180339887…    1/φ = 0.6180339887…    φ² = 2.618    √0.618 = 0.786

RETRACEMENTS   0.236   0.382   0.500*  0.618   0.705*  0.786†  0.886†
EXTENSIONS     1.272†  1.618   2.000*  2.618   4.236
                                          * not Fibonacci   † square roots

Break-even win rate at retracement r, stop at leg origin, target the high:
        R = r / (1 − r)          break-even = 1 − r
        0.382 → need 61.8%       0.618 → need 38.2%       0.786 → need 21.4%

Anchors     completed impulse leg, wick-to-wick, scale matched, never adjusted
Confluence  ≥ 2 independent non-Fibonacci factors, or no trade
Trigger     required — the zone is a location, not a signal
Stop        beyond structure + ATR buffer, never just behind the line
Invalid     a CLOSE beyond the leg origin
```

---

## 10. Reading list

**Primary sources, roughly in order of usefulness to a working trader:**

- Constance Brown, *Fibonacci Analysis* (Bloomberg/Wiley, 2008) — start here.
  Largely devoted to correcting how the tool is misapplied, which is the part
  everyone needs and no free guide covers.
- Frost & Prechter, *Elliott Wave Principle* (1978) — the wave-relationship
  guidelines, and a clear statement that they are guidelines.
- Larry Pesavento, *Fibonacci Ratios with Pattern Recognition* (1997) — where
  the ratios were fitted to Gartley's pattern.
- Scott Carney, *Harmonic Trading*, vols. 1–2 — the most rule-bound, and hence
  most testable, Fibonacci framework.
- H.M. Gartley, *Profits in the Stock Market* (1935) — historical interest: the
  original pattern, before the ratios.
- Robert Fischer, *Fibonacci Applications and Strategies for Traders*.

**For the sceptical case, read the tests, not the essays:** the *Expert Systems
with Applications* (2021) study and the arXiv retracement-distribution survey are
the two most substantive, and both are linked below.

---

## Sources

Mathematics, history, and mechanics:

- [Fibonacci retracement — Wikipedia](https://en.wikipedia.org/wiki/Fibonacci_retracement)
- [Fibonacci Retracements — StockCharts ChartSchool](https://chartschool.stockcharts.com/table-of-contents/chart-analysis/chart-annotation-tools/fibonacci-retracements)
- [Fibonacci Retracements and Extensions — CME Group](https://www.cmegroup.com/education/courses/technical-analysis/fibonacci-retracements-and-extensions)
- [How to Use Fibonacci Retracements — BabyPips](https://www.babypips.com/learn/forex/fibonacci-retracement)
- [Fibonacci Retracement is NOT Foolproof — BabyPips](https://www.babypips.com/learn/forex/when-fibonacci-fails)
- [Learn Forex: Fibonacci Retracements — FXCM](https://www.fxcm.com/markets/insights/learn-forex-fibonacci-levels/)
- [Gann's 50 Percent Retracement Theory](https://www.dummies.com/article/business-careers-money/personal-finance/investing/general-investing/how-to-use-the-gann-50-percent-retracement-theory-189985/)
- [Fibonacci retracement drawing tool — TradingView](https://www.tradingview.com/support/solutions/43000518158-fib-retracement/)
- [Fibonacci Retracements — Optuma (log vs linear)](https://www.optuma.com/kb/optuma/tools/fibonacci/fibonacci-retracements)

Evidence and criticism:

- [Automatic identification and evaluation of Fibonacci retracements: empirical evidence from three equity markets — *Expert Systems with Applications*, 2021](https://www.sciencedirect.com/science/article/abs/pii/S0957417421012495)
- [Survey on log-normally distributed market-technical trend data — arXiv:1605.03559](https://arxiv.org/pdf/1605.03559)
- [The Fibonacci Trading Myth: data debunked — Liberated Stock Trader](https://www.liberatedstocktrader.com/how-to-use-fibonacci-retracement/)
- [I tested Fibonacci Trading Strategy 100 times — Trading Rush](https://tradingrush.net/i-tested-fibonacci-trading-strategy-100-times-to-find-the-truth-about-fibonacci-retracements/)
- [Technical Analysis in Statistical Arbitrage I: Fibonacci Retracement — Presto Research](https://www.prestolabs.io/research/technical-analysis-in-statistical-arbitrage-i-fibonacci-retracement)
- [The Fibo Retracement Phenomenon — McClellan Financial](https://www.mcoscillator.com/learning_center/kb/chart_interpretation/fibo_retracement_phenomenon/)
- [Fibonacci Retracement Trading Strategy: rules and backtest — QuantifiedStrategies](https://www.quantifiedstrategies.com/fibonacci-trading-strategy/)
- [Do Fibonacci Retracements Really Work? — Morpher](https://www.morpher.com/blog/do-fibonacci-retracements-work)

Forum threads:

- [Why Fibonacci Retracements are Bullocks — Forex Factory](https://www.forexfactory.com/thread/post/1740613)
- [Why do people use Fibonacci in trading? — Forex Factory](https://forexfactory.com/showthread.php?t=418659)
- [Difference between Fibonacci extensions, projections and expansions? — Forex Factory](https://www.forexfactory.com/thread/245375-difference-between-fibonacci-extensions-projections-and-expansions)
- [What is Fibonacci retracements strategy in forex trading? — Forex Factory](https://www.forexfactory.com/thread/1133185-what-is-fibonacci-retracements-strategy-in-forex-trading)
- [How to draw and identify correctly swing high and lows — BabyPips forum](https://forums.babypips.com/t/how-to-draw-and-identify-correctly-swing-high-and-lows-for-fibo-retracement/54026)
- [Having trouble identifying swing highs/lows — BabyPips forum](https://forums.babypips.com/t/having-trouble-identifying-swing-highs-lows-for-fibonacci-retracement/48965)
- [Fibonacci Indicator tool — how do you place the fibs — BabyPips forum](https://forums.babypips.com/t/fibonacci-indicator-tool-how-do-you-place-the-fibs/687720)
- [Algorithm to accurately find swing & internal points — MQL5 forum](https://www.mql5.com/en/forum/493707)
- [How to use repainting of ZigZag — MQL5 forum](https://www.mql5.com/en/forum/181098)
- [AutoFibo of two last swings based on ZigZag — MQL5 forum](https://www.mql5.com/en/forum/475317)

Schools of practice:

- [Fibonacci Relationships — Elliott Wave International](https://www.elliottwave.com/waveopedia/fibonacci-relationships/)
- [Wave Ratios and Measurements — eSignal manual, ch. 10 (PDF)](https://www.esignal.com/publicdocs/eSignal_Manual_ch10.pdf)
- [Harmonic Patterns — StockCharts ChartSchool](https://chartschool.stockcharts.com/table-of-contents/trading-strategies-and-models/trading-strategies/harmonic-patterns)
- [Optimal Trade Entry — LuxAlgo concept library](https://www.luxalgo.com/library/concept/optimal-trade-entry/)
- [Optimal Trade Entry in ICT (PDF) — HowToTrade](https://howtotrade.com/wp-content/uploads/2024/05/Optimal-Trade-Entry-in-ICT.pdf)
- [The Golden Pocket — TradingView](https://www.tradingview.com/chart/BTCUSDT/4B53pR2B-The-Golden-Pocket-Fibonacci-s-Sweet-Spot-in-Trading/)
- [Multi-Timeframe Fibonacci Levels — LuxAlgo](https://www.luxalgo.com/blog/multi-timeframe-fibonacci-levels-explained/)
- [Fibonacci Analysis, Constance Brown — Wiley](https://www.wiley.com/en-us/Fibonacci+Analysis-p-9780470885253)

Automation and testing:

- [Swing High/Low market-structure concept — LuxAlgo](https://www.luxalgo.com/library/concept/swing-high-low/)
- [Fibonacci Retracement: strategy and Python implementation — QuantInsti](https://blog.quantinsti.com/fibonacci-retracement-trading-strategy-python/)
- [How to backtest your Fibonacci trading strategy — YWO](https://ywo.com/blog/backtest-fibonacci-strategy/)
- [Fibonacci Time Zones — MetaTrader 5 help](https://www.metatrader5.com/en/terminal/help/objects/fibo/fibo_timezones)
- [Avoid these common mistakes with Fibonacci retracements — Axiory](https://www.axiory.com/trading-resources/technical-indicators/fibonacci-retracements-mistakes/)
- [Fibonacci retracements & mistakes to avoid — Trade2Win](https://www.trade2win.com/articles/fibonacci-retracements-mistakes-to-avoid)
