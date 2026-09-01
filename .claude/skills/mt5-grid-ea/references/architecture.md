# Grid EA architecture notes

Reusable structure, extracted from `mt5/GridBot_2X_AutoUpdate.mq5` and from what
the failure modes in `gridbot-2x-review.md` imply.

## The state a grid EA actually has

| State | Lives for | Must survive restart? |
|---|---|---|
| Anchor price | One cycle | Yes — otherwise the new grid centres wrong around live positions |
| Grid step | One cycle | Yes — the level→price mapping depends on it |
| Peak basket profit | One basket | No — resets to 0 on a new cycle anyway |
| Paused-after-loss flag | Until operator intervenes | **Yes** — losing it re-arms the strategy |
| Daily loss lock timestamp | Until next broker day | **Yes** — same |
| Restart cooldown | Seconds | No |

The two rows in bold are the ones most implementations get wrong. The test is
not "is this convenient to persist" but "does losing it let the EA trade against
its own rules". Persist those, flush them, restore them in `OnInit`, and validate
what you restored before trusting it.

## Single-entry management, invoked from three events

```
OnTick ─┐
OnTimer ─┼──> ManageEA()   // one reentrancy guard, one exit path
OnTradeTransaction ─┘
```

This is a good pattern: the timer guarantees progress on a quiet symbol, the tick
gives responsiveness, and the transaction hook reacts immediately to a fill. Three
requirements come with it:

1. **A reentrancy guard** (`g_manage_busy`) so a transaction fired mid-pass does
   not re-enter.
2. **Exactly one exit path** that clears the guard and refreshes the dashboard —
   every early return must go through it, or the EA deadlocks itself.
3. **A filter in `OnTradeTransaction`**, on both `trans.symbol` and `trans.type`.
   Without it the handler fires several times per fill and for every symbol in the
   terminal.

## Ordering inside a management pass

Order matters, because each stage can make the later ones unnecessary:

```
1. closing in progress?      -> continue unwinding, return
2. daily lock expired?       -> release, start a cycle
3. daily loss breached?      -> lock, start closing, return
4. daily lock active?        -> return
5. positions open?           -> profit target / trail / emergency / drawdown
6. outside session?          -> optionally delete pendings, return
7. restart cooldown?         -> return
8. no anchor?                -> start a cycle
9. recentre if flat
10. maintain the ladder
```

The invariant: **every exit check runs before every entry action.** An EA that
places an order and then discovers it was over its daily loss limit has already
lost.

## Exit path: pendings first, always

```cpp
DeleteManagedOrders();     // no new level can fill into a basket being unwound
CloseManagedPositions();
if(HasManagedExposure()) return;   // not done — retry next pass
// only now: clear persisted cycle state, decide restart vs pause
```

Making the close *resumable* rather than a single blocking loop is right: a
delete or close can be rejected (freeze level, requote), and the next pass picks
up where this one stopped. But then the retry needs a way to report a persistent
blocker, or it retries forever in silence.

## Basket exits, and what each is for

- **Fixed money target** — the primary exit. Gross unless you subtract
  commission; see the review, finding 4.
- **Profit trail** (start tracking above X, close after giving back Y) — converts
  a basket that reached most of the target and stalled into a smaller win. Needs
  `peak` reset exactly where the cycle resets.
- **Emergency loss** (absolute money) — a hard floor. Should pause, not restart.
- **Drawdown percent of balance** — scales the floor with the account. Balance,
  not equity: equity already contains the floating loss being measured, so an
  equity-based percentage compares a number against itself.
- **Daily loss limit** (realised + floating) — the only guard that spans cycles,
  and therefore the only one that needs a persisted timestamp.

The first two restart; the last three stop. Keep that distinction visible in the
code — `StartBasketClose(pause_after_close, reason)` with an explicit boolean is
a good shape, because it forces the caller to decide.

## Level → price, and recovering it

```
buy  level n price = anchor - n * step
sell level n price = anchor + n * step
```

Invertible, which is what makes anchor recovery possible after a restart: read any
managed order, recover `anchor = price + n*step` (buy) or `price - n*step` (sell).
Two conditions for that to work:

- The step must be **frozen for the cycle**. Recompute it per level under ATR
  spacing and the mapping stops being invertible.
- You must know `n` for an existing order. That is the identity problem — solve
  it with the magic number, not the comment.

Prefer recovering from persisted state, and treat inference as the fallback. When
inferring, cross-check several orders rather than trusting the first.

## Volume ladder

```cpp
volume(level) = NormalizeVolume(base * pow(multiplier, level - 1));
```

Read the multiplier as capital required: `2.0` is `2^n`, `1.0` is a flat grid at
`n`, and values between give `((m^n)-1)/(m-1)`. Print the full ladder and its sum
once in `OnInit` — the operator should see 0.01/0.02/0.04/0.08/0.16 = 0.31 lots
rather than infer it from a multiplier input.

The cap interacts with the ladder: once `InpMaximumLot` binds, every deeper level
returns the same volume and the progression flattens. That is the safe behaviour,
but it silently changes the strategy, so log it the first time it happens.

## Layered exposure limits

Four independent limits, each catching what the others miss:

1. `InpMaximumLot` — one order.
2. `InpMaximumTotalVolume` — positions plus pending volume. **The load-bearing
   one**, because it is the only limit that does not depend on how the broker
   prices margin.
3. `InpMinimumMarginLevelPercent` — account health, checked before adding.
4. `InpMarginReservePercent` — free margin as a multiple of estimated order
   margin.

Limits 3 and 4 rest on `OrderCalcMargin`, which ignores existing exposure and
usually returns ~0 for forex pendings. Treat them as advisory and keep limit 2 set
to a real number.

## Dashboard

`Comment()` is the cheapest operator interface there is, and a grid EA needs one —
an operator who cannot see the anchor, the step, the basket P&L, the peak, and
whether a lock is active cannot judge whether to intervene. Show the *reason* for
the current state, not just the state: "Free-margin reserve blocks new limits"
answers the operator's actual question, where "Idle" does not.

Rebuild it on the timer rather than on every tick; it is as expensive as the
trading logic.
