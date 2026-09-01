---
name: mql5-trade-safety
description: Broker- and platform-level correctness rules for any MQL5 code that sends orders — filling modes, stops/freeze levels, volume normalisation, order identification, margin checks, retcode handling, and state that must survive a terminal restart. Use whenever writing, reviewing, or debugging an MQL5 Expert Advisor, script, or service that calls OrderSend, CTrade, BuyLimit/SellLimit/PositionOpen/PositionClose/OrderDelete, or when diagnosing MT5 trade retcodes such as 10016 invalid stops, 10030 unsupported filling mode, 10014 invalid volume, or 10024 too many requests.
---

# MQL5 trade safety

Rules that apply to *any* EA that sends an order. Strategy logic can be right and
the EA still lose money because a broker rejected half its orders. This skill is
about the layer between your strategy and the server.

Load `references/retcodes.md` when diagnosing a specific rejection, and
`references/preflight.md` for the full order-submission checklist.

## The rule that matters most

**Never trust a value you did not compute yourself, and never trust that a
request succeeded because the function returned `true`.**

`CTrade` methods return `true` when the request was *sent*, not when it was
*filled*. Always check the retcode too:

```cpp
bool sent = trade.BuyLimit(volume, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, tag);
uint code = trade.ResultRetcode();
bool ok = sent && (code == TRADE_RETCODE_DONE ||
                   code == TRADE_RETCODE_PLACED ||
                   code == TRADE_RETCODE_DONE_PARTIAL);
```

`TRADE_RETCODE_DONE_PARTIAL` is not a success you can ignore: you asked for one
volume and got another, and the remainder may still be sitting as a live order.

## Identify your orders by magic number, never by comment

Brokers may rewrite, append to, or truncate the comment field (it is limited to
about 31 characters, and broker additions eat into that budget). Comments cannot
be modified after placement, and a partial close does not inherit the parent's
comment — the new position's comment comes back empty.

So this is unsafe:

```cpp
if(OrderGetString(ORDER_COMMENT) == "MYEA:B:3")   // broker may have changed it
```

The magic number is yours and the server preserves it. When you need more than
one bit of state per order — a grid level, a basket id, a strategy slot — encode
it in the magic number, or keep an in-memory ticket→state map that you rebuild in
`OnInit` from ticket and price rather than from text.

Anything that identifies an order by comment must degrade safely: ask what
happens when the comment comes back empty. Usually the answer is "the EA thinks
the order does not exist and places a duplicate", which is exactly the failure
you cannot afford.

## Distance rules: check both levels, on placement and on deletion

`SYMBOL_TRADE_STOPS_LEVEL` is the minimum distance from market at which you may
*set* a stop, target, or pending price. `SYMBOL_TRADE_FREEZE_LEVEL` is the band
inside which you may not *modify or delete* an existing order. Checking only the
first is the usual cause of retcode 10016.

```cpp
int    stops  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
int    freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
double margin = MathMax(MathMax(stops, freeze) * _Point,
                        SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
```

Freeze level matters most on the *exit* path. An EA closing a basket deletes its
pending orders first; a pending order that has drifted inside the freeze band
cannot be deleted, so the close loop stalls until price moves away. Detect that
case and report it rather than retrying silently forever.

Both values are frequently `0` on retail forex and non-zero on indices, metals,
and exchange instruments — so a strategy that tests clean on EURUSD can reject
every order on US30. Re-read them in `OnInit`; do not hardcode.

## Filling modes: pending orders are not market orders

Pending orders must use `ORDER_FILLING_RETURN`, whatever the symbol's execution
mode says, because they are filled later under rules the broker sets at that
time. `CTrade::SetTypeFillingBySymbol()` resolves the symbol's *market* policy —
it will pick FOK when both FOK and IOC are allowed — which is the right answer
for `PositionOpen` and the wrong one for `BuyLimit`.

Whether `CTrade` overrides this for you depends on your `Trade.mqh` build, so do
not assume. If pending orders come back 10030, set the policy explicitly around
the call:

```cpp
trade.SetTypeFilling(ORDER_FILLING_RETURN);   // pending orders
trade.BuyLimit(...);
trade.SetTypeFillingBySymbol(_Symbol);        // restore for market orders
```

## Normalise volume and price against the symbol, always

Price must land on a `SYMBOL_TRADE_TICK_SIZE` boundary — which is not always
`_Point`. Round *away* from the market for a limit order so rounding never pushes
the price through the current quote:

```cpp
double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
if(ts <= 0.0) ts = _Point;
double price = is_buy ? MathFloor(raw / ts + 1e-9) * ts    // buy limit: down
                      : MathCeil (raw / ts - 1e-9) * ts;   // sell limit: up
price = NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
```

Volume must be a multiple of `SYMBOL_VOLUME_STEP` between `SYMBOL_VOLUME_MIN`
and `SYMBOL_VOLUME_MAX`. Watch the ordering of your clamps: applying your own
cap and then `MathMax(v, SYMBOL_VOLUME_MIN)` silently *violates* your cap when
the symbol minimum is larger than it. When your risk cap is below the tradable
minimum, the correct answer is to place nothing and say so — not to round up.

## Margin checks are an estimate, not a guarantee

`OrderCalcMargin` computes the requirement for one hypothetical order **ignoring
your existing positions and pending orders**. On forex, pending orders usually
reserve no margin at all; on exchange instruments they may. So a per-order check
tells you nothing about what happens when several pending orders fill at once
during a fast move.

If your EA can have N pending orders that could all trigger together, budget for
the summed margin of all N, not for the next one. Cap total exposure by volume as
well, because that cap holds regardless of how the broker prices margin.

## State that must survive a restart

Terminal global variables (`GlobalVariableSet`) persist across restarts and are
the simplest place to keep a scalar. Two caveats:

- Call `GlobalVariablesFlush()` after writing anything you cannot afford to lose.
  Otherwise an unclean terminal exit can drop the most recent value.
- They expire after four weeks without access, and hold `double` only. For
  structured state, write a file under `MQL5/Files`.

The test to apply: **list every piece of state whose loss would make the EA
resume trading against its own risk rules.** A "paused after emergency loss" flag
and a "locked until tomorrow after daily loss limit" timestamp are exactly that —
if they live only in memory, a recompile re-arms the strategy the guard was
meant to stop. Persist those before you persist anything convenient.

## Do not do real work on every tick

`HistorySelect()` costs roughly 5–30 ms per call and is easily the most expensive
thing an EA does routinely; several calls can consume seconds inside one
`OnTick`. Never put it on the unconditional tick path. Recompute realised P&L
when a deal actually closes — in `OnTradeTransaction` — and cache it.

`OnTradeTransaction` also needs a filter. It fires many times per fill, once per
transaction type, for **every symbol in the terminal**. Handle the types you care
about and return early otherwise:

```cpp
if(trans.symbol != _Symbol)                    return;
if(trans.type != TRADE_TRANSACTION_DEAL_ADD &&
   trans.type != TRADE_TRANSACTION_ORDER_DELETE) return;
```

Otherwise every other EA's activity drags your full O(n) scans through the CPU.

## Account mode is a hard precondition

Grid, hedge, and multi-slot strategies require a hedging account; on a netting
account the platform merges same-symbol positions and the strategy silently means
something else. Check it in `OnInit` and refuse to run:

```cpp
if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
   != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   return INIT_FAILED;
```

Do the same for the other preconditions: `TERMINAL_TRADE_ALLOWED`,
`MQL_TRADE_ALLOWED`, `ACCOUNT_TRADE_ALLOWED`, and `SYMBOL_TRADE_MODE` not being
`DISABLED` or `CLOSEONLY`.

## Rate limits are real

Deleting and re-placing a whole ladder of orders in one pass, on every tick, will
eventually earn `TRADE_RETCODE_TOO_MANY_REQUESTS` (10024) — or a warning from the
broker. Rebuild structures on a timer or a new bar, not on tick, and put a
cooldown between bulk operations.

## Logging that survives a burst

A single global "log at most one error per N seconds" throttle hides exactly the
information you need: when five levels fail at once, you see one. Throttle per
error *kind* instead, and always print retcode, retcode description, and broker
comment together — the broker comment is often the only text that names the real
cause.
