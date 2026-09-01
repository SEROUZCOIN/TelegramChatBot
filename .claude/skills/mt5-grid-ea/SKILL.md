---
name: mt5-grid-ea
description: Design, review, and safely extend MetaTrader 5 grid and martingale basket Expert Advisors — laddered limit orders, lot progression, basket profit targets and trailing, cycle restart, anchor recentring, ATR-adaptive spacing, trend-direction filters, and equity/drawdown kill switches. Use when working on GridBot_2X_AutoUpdate.mq5 or any MQL5 EA that maintains a grid of pending orders, scales lots after a losing level, closes positions as a basket rather than individually, or when asked whether a grid/martingale EA is safe to run.
---

# MT5 grid and martingale EAs

A grid EA is a small amount of trading logic wrapped around a large amount of
risk management. Reviews that only read the entry logic miss the part that
actually decides whether the account survives.

The worked example throughout is `mt5/GridBot_2X_AutoUpdate.mq5`. Its full audit
is in `references/gridbot-2x-review.md`; the reusable architecture notes are in
`references/architecture.md`. For broker- and platform-level correctness — filling
modes, stops and freeze levels, volume normalisation, retcodes — use the
`mql5-trade-safety` skill instead; this skill assumes those rules and does not
repeat them.

## Start from the risk arithmetic, not the code

Before reading a line of a grid EA, work out what it costs to be wrong.

A martingale ladder that doubles needs roughly `2^n` units of capital to survive
`n` adverse levels: ten levels is about 1,024 units. A pure grid with fixed lots
needs about `n(n+1)/2` — around 55 for the same ten levels, roughly eighteen
times less. Taranto & Khan (2020) showed the grid problem and the gambler's-ruin
problem are mathematically distinct processes with different loss-accumulation
rates, and that difference is the whole reason a grid can be run at all.

The multiplier is therefore the single most consequential input in the file. For
`GridBot_2X_AutoUpdate.mq5` at its defaults — base 0.01, multiplier 2.0, five
levels — the ladder is 0.01 / 0.02 / 0.04 / 0.08 / 0.16, totalling 0.31 lots, and
level five carries 16× the risk of level one. Five levels is survivable; the same
code at ten levels is not, and nothing in the file stops an operator setting ten.

State this number explicitly in any review. "The EA has a drawdown guard" is not
an answer to "what does level 8 cost".

## The failure mode is sudden, and that is the point

Grid win probability stays high and stable across many levels and then collapses
near a threshold. The equity curve looks excellent for a long time *while the
ruin probability is already climbing*. A backtest that shows smooth profit is
therefore weak evidence — it is the expected appearance of a system that has not
yet met its bad month.

When reviewing, ask what the EA does in the tail, not in the average case:

- What is the largest adverse excursion it can absorb before margin call?
- Does anything stop it re-entering immediately after taking that loss?
- Is the give-up point a *hard* rule, or does it depend on state held in RAM?

Every grid system needs an explicit give-up point: stop adding and wait, cut and
reset, or hedge the exposure. An EA without one is not a strategy, it is a
leverage schedule.

## The four mechanisms to check in order

**1. Slot identity.** A grid maintains "one order per level per side". How does
the EA know a level is already occupied? If the answer is the order comment, it
is fragile — brokers rewrite and truncate comments, and a partially closed
position comes back with an empty one. A false "this level is empty" places a
duplicate, which breaks the lot ladder and the exposure cap at the same time.
Prefer magic-number encoding or a rebuilt ticket→level map.

**2. Basket accounting.** Grid EAs exit as a basket, so the exit trigger is a sum
over positions. Two things go wrong here routinely:

- *Commission is missing.* MQL5 has no `POSITION_COMMISSION`; commission lives on
  deals (`DEAL_COMMISSION`). A floating-profit sum of `POSITION_PROFIT + SWAP` is
  **gross**, so a basket that closes at a +10.00 target realises less than 10.00.
  With many small baskets that gap is the strategy's entire edge.
- *Realised and floating are computed inconsistently.* If the daily-loss check
  includes commission but the profit target does not, the two guards disagree
  about what a dollar is.

**3. Cycle boundaries.** Where does one basket end and the next begin? Check that
the anchor price, the step size, the peak-profit high-water mark, and any pause
flag are all reset together at exactly one place, and that a restart cannot begin
while the previous basket still has exposure. Delete pendings *before* closing
positions on the exit path, or a level can fill into a basket you are unwinding.

**4. The kill switches, and whether they survive a restart.** This is where grid
EAs are most often quietly broken. A pause flag or daily-lock timestamp held only
in a global variable is lost on recompile, reattach, or terminal restart — so the
guard that fired to stop the strategy silently re-arms it. Any state whose loss
would let the EA resume trading against its own rules must be persisted and
flushed, and re-read in `OnInit`.

## Adaptive spacing and direction filters

ATR-based spacing is a real improvement over a fixed step: it widens the grid when
volatility rises, which is when a fixed grid fills every level at once. Two
implementation details decide whether it helps:

- **Read the indicator from the last closed bar** (`CopyBuffer(h, 0, 1, 1, buf)`),
  not the forming one, so spacing does not flicker intrabar and orders are not
  cancelled and re-placed on noise.
- **Freeze the step for the life of a cycle.** If spacing changes while a ladder
  is live, the level→price mapping stops matching the orders on the server, and
  anchor recovery after a restart infers the wrong anchor.

Trend filters (fast/slow EMA with a neutral band) narrow a grid to one side. They
reduce exposure but do not change the tail: a grid that only buys dips still
ladders all the way down in a downtrend. Treat a direction filter as an efficiency
improvement, never as a risk control.

Note the interaction to check: when the filter flips, the EA deletes the orders of
the disallowed side. If that deletion is comment-driven, the stripped-comment
orders survive the flip and sit on the server unmanaged.

## Recentring: the quiet order-flood risk

Moving an untouched grid with price is sensible. But "delete N orders and place N
orders" on a threshold of one grid step, evaluated on every tick, is a lot of
traffic — enough to reach `TRADE_RETCODE_TOO_MANY_REQUESTS`. Recentre on a timer
or a new bar, require a threshold of more than one step, and add a cooldown.

## What to say when asked "is this safe to run"

Answer in this shape, and be concrete:

1. The exposure at the deepest level, in lots and in account currency.
2. The adverse move (in points and in ATRs) that reaches that level.
3. Whether the guards that stop it are persistent or in-RAM only.
4. Whether the account can absorb (1) at (2) with the guards disabled — because
   that is the state after any restart, if (3) says in-RAM.

Then give the recommendation. Never present a grid EA as safe because its
backtest is smooth; see the failure-mode section above for why that curve is
uninformative.

## Testing a grid EA

- **Every tick based on real ticks.** "Open prices only" cannot model a ladder.
- **Force the tail.** Test across a known trending stretch, not a calm range —
  the range months are the ones that look good regardless.
- **Restart mid-basket.** Attach, let levels fill, remove the EA, re-attach.
  Confirm it recovers the anchor rather than building a second grid on top of the
  first, and confirm any tripped guard is still tripped.
- **Test on an index CFD**, not only forex: non-zero stops level and integer lot
  steps break assumptions that hold on EURUSD.
