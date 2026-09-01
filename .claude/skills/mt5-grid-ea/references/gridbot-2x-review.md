# Audit: GridBot_2X_AutoUpdate.mq5

Findings against v2.00 of `mt5/GridBot_2X_AutoUpdate.mq5`, most severe first.
Line numbers are from **v2.00**; the file in this repo is now v3.00, which
applies the fixes and adds auto-configuration. The findings are kept in full
because they are the worked examples the skill teaches from — each one is a
mistake that is easy to make again.

## Remediation status in v3.00

| # | Finding | Status in v3.00 |
|---|---|---|
| 1 | Slot identity via order comment | Fixed — identity moved into the magic number (`SlotMagic`, `DecodeSlotMagic`); comments are labels only |
| 2 | Risk guards lost on restart | Fixed — `g_paused` and `g_daily_lock_until` persisted and restored in `OnInit` |
| 3 | No `GlobalVariablesFlush()` | Fixed — `SaveState()` flushes; also called from `OnDeinit` |
| 4 | Gross profit target | Fixed — exit commission per lot learned from closed deals and subtracted |
| 5 | `HistorySelect` on the tick path | Fixed — cached, recomputed on `DEAL_ADD` and day roll |
| 6 | Unfiltered `OnTradeTransaction` | Fixed — filtered on `trans.symbol` and `trans.type` |
| 7 | Freeze level unchecked | Fixed — `MinimumOrderDistancePrice()` takes `max(stops, freeze)`; frozen deletes reported distinctly |
| 8 | Pending-order filling mode | Fixed — `ORDER_FILLING_RETURN` set around each pending, restored after |
| 9 | Global log throttle | Fixed — throttled per retcode |
| 10 | `NormalizeVolume` cap violation | Fixed — returns 0 and skips when the symbol minimum exceeds the cap |
| 11 | Margin checked per order | Fixed — reserve budgeted against the whole ladder's lots |
| 12 | Anchor inference takes first match | Fixed — median across all managed orders and positions |
| 13 | Recentring order flood | Fixed — default threshold 2 steps plus a cooldown |
| 14 | Cosmetic | Fixed — `#property strict` removed, dashboard throttled to 1 Hz |

v3.00 also adds the auto-configuration layer described in
`architecture.md`, which introduces its own thing to review: the ladder solver
is only as honest as its risk model. Its stated contract is that a fully filled
ladder plus one more step of adverse movement costs about
`InpRiskPercentPerCycle` of equity — that is a *per-side* worst case, and it
assumes the step holds. A gap straight through the ladder, or a symbol whose
tick value moves with price, will exceed it.

The EA is well above the average grid bot: it requires a hedging account, refuses
bad inputs, normalises volume and price, checks retcodes, caps total exposure,
guards margin level and free margin, and has profit-trail, emergency-loss,
drawdown and daily-loss exits. The findings below are the gaps in that structure,
not a claim that the structure is absent.

## 1. Slot identity rests on order comments — duplicate orders (high)

`SlotExists()` (499) decides whether a grid level is occupied by string-comparing
`ORDER_COMMENT` / `POSITION_COMMENT` against `SlotTag()` (89). Brokers may rewrite,
append to, or truncate comments — the field is roughly 31 characters and broker
additions consume part of it — and a partially closed position comes back with an
empty comment.

When a comment does not survive, `SlotExists()` returns false and `MaintainGrid()`
(733) places a **second** order at the same level. That breaks the martingale
ladder and the `InpMaximumTotalVolume` cap in the same step, because the cap is
checked per order against the current total rather than against the intended plan.

The same weakness hits three other paths:

- `IsSlotOrderSide()` / `DeleteManagedSideOrders()` (316, 322) — when the trend
  filter flips sides, orders whose comment was stripped are not deleted and stay
  live on the disallowed side, unmanaged.
- `InferAnchorFromExistingOrders()` / `...Positions()` (569, 599) — anchor
  recovery after a restart depends entirely on comments.
- Basket close is unaffected (it deletes by magic, not comment), so the failure is
  asymmetric: the EA reliably closes, but unreliably avoids duplicating.

**Fix:** encode side and level in the magic number, e.g.
`magic = InpMagicNumber + side*100 + level`, and match on `ORDER_MAGIC`. Keep the
comment as a human-readable label only. If the magic must stay single-valued,
rebuild a ticket→level map in `OnInit` from order prices relative to the anchor,
and treat comments as a hint that is verified against price.

## 2. Risk guards do not survive a restart (high)

`g_paused` (75) and `g_daily_lock_until` (79) are plain globals. `SaveAnchor()`
(109) persists only the anchor and step.

So: emergency loss fires → `g_paused = true` → EA stops. The operator recompiles,
changes an input, or the terminal restarts → `OnInit` runs → `g_paused` is false →
**the EA immediately builds a new grid on the account it just blew a guard on.**
Identically for the daily loss lock, which is meant to hold until the next broker
day.

This inverts the intent of both guards, and it triggers on the most ordinary
operator action there is.

**Fix:** persist both to terminal global variables next to the anchor, restore
them in `RestoreOrCreateAnchor()`, and call `GlobalVariablesFlush()` after every
write. Which leads to:

## 3. `GlobalVariablesFlush()` is never called (medium)

`SaveAnchor()` (109) writes but never flushes. Terminal global variables persist
across restarts, but an unclean exit can lose the most recent unflushed value —
so the anchor can come back stale, and the EA rebuilds a grid at the wrong centre
around live positions. One line, at the end of `SaveAnchor()`.

## 4. The profit target is gross, so realised profit is below target (medium)

`ManagedFloatingProfit()` (281) sums `POSITION_PROFIT + POSITION_SWAP`. MQL5 has
no `POSITION_COMMISSION` — commission is a deal property — so the sum excludes
round-turn commission entirely.

`InpBasketProfitMoney` defaults to 10.00 while the default ladder is 0.31 lots
across up to five positions. On a commissioned account, five round turns can be a
meaningful fraction of that 10.00, and the trail exit (`InpTrailGivebackMoney`,
2.00) is measured in the same inflated units.

Note the inconsistency: `ManagedProfitToday()` (438) *does* include
`DEAL_COMMISSION` and `DEAL_FEE`. The daily-loss guard and the profit target
therefore measure money differently.

**Fix:** subtract an estimated round-turn commission per open position from the
floating sum, or document that the money inputs are gross and must be set with
commission added by the operator.

## 5. `HistorySelect()` on the tick path (medium)

`ManagedProfitToday()` (438) calls `HistorySelect()` over the whole broker day and
walks every deal. It runs from `ManageEA()` on every invocation whenever
`InpDailyLossLimitMoney > 0` — and `ManageEA()` is wired to `OnTick` (1081),
`OnTimer` at 1 Hz (1057, 1086) **and** `OnTradeTransaction` (1091).

`HistorySelect` costs roughly 5–30 ms per call; several can consume seconds inside
one tick. On an active symbol this is the EA's dominant cost and it delays the
order placement the EA exists to do.

**Fix:** cache the day's realised total and recompute it only in
`OnTradeTransaction` on `TRADE_TRANSACTION_DEAL_ADD`, plus once when the broker
day rolls over.

## 6. `OnTradeTransaction` is unfiltered (medium)

`OnTradeTransaction` (1091) calls `ManageEA()` unconditionally. It fires several
times per fill — once per transaction type — and for **every symbol in the
terminal**, so on a multi-symbol setup another EA's activity drags this one
through full `OrdersTotal()` / `PositionsTotal()` scans and, per finding 5, a
`HistorySelect`.

**Fix:** return early unless `trans.symbol == _Symbol` and `trans.type` is
`TRADE_TRANSACTION_DEAL_ADD` or `TRADE_TRANSACTION_ORDER_DELETE`.

## 7. Freeze level is not checked, and it stalls basket close (medium)

`PlaceGridOrder()` (671) uses `SYMBOL_TRADE_STOPS_LEVEL` only.
`SYMBOL_TRADE_FREEZE_LEVEL` governs *modification and deletion* of an existing
order, and it is the one that bites on the exit path: `ContinueBasketClose()`
(783) deletes pendings first, and a pending order that has drifted inside the
freeze band cannot be deleted. `g_cycle_closing` stays true and the EA retries
every tick and timer pass, logging at most one message per 10 seconds
(finding 9), until price moves away.

Both levels are commonly 0 on retail forex and non-zero on indices and metals, so
this will not reproduce on EURUSD.

**Fix:** take `MathMax(stops_level, freeze_level)` for placement distance, and in
the close loop detect a delete rejected for freeze and report it distinctly rather
than retrying silently.

## 8. Pending orders may hit retcode 10030 (medium — verify on your build)

`OnInit` calls `trade.SetTypeFillingBySymbol(_Symbol)` (1025), which resolves the
symbol's **market** filling policy and picks FOK when both FOK and IOC are
allowed. Pending orders must use `ORDER_FILLING_RETURN` regardless of the symbol's
execution mode, because they fill later under rules the broker sets then.

Whether `CTrade::OrderOpen` (behind `BuyLimit`/`SellLimit`) overrides the stored
policy depends on the `Trade.mqh` build shipped with the terminal, so this is a
"confirm, then fix" item rather than a certain defect. If pending orders come back
10030, wrap the calls:

```cpp
trade.SetTypeFilling(ORDER_FILLING_RETURN);
sent = is_buy ? trade.BuyLimit(...) : trade.SellLimit(...);
trade.SetTypeFillingBySymbol(_Symbol);
```

## 9. Error logging collapses bursts (medium)

`LogTradeFailure()` (532) throttles to one message per 10 seconds **globally**.
`MaintainGrid()` places up to `2 × InpLevelsPerSide` orders in one pass, so when a
symbol-wide condition rejects all of them, the log shows one line and nine silent
failures. The same throttle hides repeated delete failures during basket close.

**Fix:** throttle per retcode, or per (action, retcode) pair.

## 10. `NormalizeVolume()` can exceed `InpMaximumLot` (low)

At 198–204 the clamp order is: apply `InpMaximumLot`, apply `SYMBOL_VOLUME_MAX`,
then `MathMax(capped, minimum)`. When `SYMBOL_VOLUME_MIN` exceeds `InpMaximumLot`
— plausible on an index CFD with a 1.0 minimum lot — the final `MathMax` silently
overrides the operator's hard cap.

Related and worth documenting rather than fixing: once the requested volume passes
`InpMaximumLot`, every deeper level returns the same capped volume, so the ladder
flattens without warning. That is safe, but it means the recovery maths the
operator assumed no longer holds.

**Fix:** when the symbol minimum exceeds the cap, refuse to place and log it once.

## 11. Margin is checked per order, not per ladder (low)

`MarginAllowsOrder()` (394) calls `OrderCalcMargin` for the single order being
placed. That function ignores existing positions and pending orders by design, and
on forex pending orders usually reserve no margin at all — so a ladder of five
pendings passes five independent checks that each see a nearly empty account, and
then all five can fill together in one fast move.

`InpMaximumTotalVolume` (1.0 by default vs 0.31 for the default ladder) is the
guard actually doing the work here. Keep it set.

## 12. Anchor inference takes the first match (low)

`InferAnchorFromExistingOrders()` (569) returns on the first order whose comment
parses, iterating from the highest index down. One stale or mis-commented order
therefore defines the anchor for the whole recovered cycle. It also reconstructs
the anchor using the *current* `CycleStepPrice()`, which under ATR spacing may
differ from the step in force when the orders were placed — giving a wrong anchor
from correct data.

**Fix:** collect all matches, derive a candidate anchor from each, and take the
median (or require agreement) rather than the first.

## 13. Recentring can flood the broker (low)

`RecenterFlatGridIfNeeded()` (818) runs from `ManageEA()` on every tick. At the
defaults (`InpAutoRecenterWhenFlat = true`, `InpRecenterAfterSteps = 1`) a move of
one grid step deletes the whole ladder and places a new one — up to 20 requests at
five levels per side. Repeated near the threshold this approaches
`TRADE_RETCODE_TOO_MANY_REQUESTS`.

**Fix:** require more than one step of drift, and add a cooldown between
recentres like the one `g_next_build_time` already provides for restarts.

## 14. Cosmetic

- `#property strict` (7) is an MQL4 directive; it has no effect in MQL5.
- The dashboard `Comment()` is rebuilt on every tick and recomputes four full
  position/order scans (485). Harmless, but it is the same cost as the logic.
- `g_daily_lock_until = ServerDayStart(now) + 86400` (885) assumes a 24-hour
  broker day; it drifts by an hour across a DST change on the server.

## Things this EA gets right — keep them in any rewrite

- Refuses to run on a netting account (1014).
- Full input validation with `INIT_PARAMETERS_INCORRECT` (983).
- Reads indicators from the **closed** bar so spacing and regime do not flicker
  intrabar (134) — this is the detail most grid EAs get wrong.
- Freezes the step for the life of a cycle (`g_cycle_step_points`), so the
  level→price mapping stays stable.
- Deletes pendings before closing positions on the exit path (786), so no level
  fills into a basket being unwound.
- Rounds limit prices away from the market by tick size (223).
- Checks the return value *and* the retcode, including `DONE_PARTIAL` (524).
- Leaves managed trades untouched on `OnDeinit`, and says so in a comment (1078).
