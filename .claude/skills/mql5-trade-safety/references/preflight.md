# Order submission preflight

Run this list against any code path that sends an order. Most of it is what the
MQL5 Market validator checks before publication, which is a decent proxy for
"will this survive contact with an unfamiliar broker".

## Before the EA trades at all — `OnInit`

- [ ] Every input validated; return `INIT_PARAMETERS_INCORRECT` on bad input,
      with a message that names which input is wrong.
- [ ] `ACCOUNT_MARGIN_MODE` matches what the strategy assumes (hedging vs netting).
- [ ] Indicator handles created once and checked against `INVALID_HANDLE`;
      released in `OnDeinit`.
- [ ] Symbol properties read and logged: digits, point, tick size, volume
      min/step/max, stops level, freeze level, filling modes.
- [ ] Persisted state restored, and restored state validated before it is trusted.

## Before each order — the request

- [ ] `TERMINAL_TRADE_ALLOWED`, `MQL_TRADE_ALLOWED`, `ACCOUNT_TRADE_ALLOWED`.
- [ ] `SYMBOL_TRADE_MODE` is not `DISABLED` or `CLOSEONLY`.
- [ ] Tick is fresh and sane: `SymbolInfoTick` succeeded, `bid > 0`, `ask > 0`.
- [ ] Spread filter applied, if the strategy has one.
- [ ] Volume normalised to `SYMBOL_VOLUME_STEP`, inside min/max, and inside your
      own cap — and the clamp order does not let the symbol minimum override
      your cap.
- [ ] Price rounded to `SYMBOL_TRADE_TICK_SIZE` in the safe direction, then
      `NormalizeDouble` to `SYMBOL_DIGITS`.
- [ ] Distance from market respects `SYMBOL_TRADE_STOPS_LEVEL`.
- [ ] Filling policy correct for the order kind — `ORDER_FILLING_RETURN` for
      pendings.
- [ ] Margin budgeted for the whole set of orders that could fill together, not
      just this one.
- [ ] Total exposure cap checked (`positions + pending volume`).

## After each order — the response

- [ ] Return value **and** retcode both checked.
- [ ] `DONE_PARTIAL` handled explicitly, not lumped in with success.
- [ ] Failure logged with retcode, description, and broker comment.
- [ ] No unbounded retry loop; failures back off.

## Before each modify or delete

- [ ] Ticket re-selected immediately before use — it may be gone.
- [ ] `SYMBOL_TRADE_FREEZE_LEVEL` respected; a rejection here is expected
      behaviour near market, not a bug to retry forever.

## Shutdown — `OnDeinit`

- [ ] Timer killed, indicator handles released, `Comment("")` cleared.
- [ ] State that guards risk is flushed to persistent storage.
- [ ] Deliberate decision about open trades, documented in the code: an EA that
      leaves positions open on removal must say so, because the operator will
      assume the opposite.

## Testing

- [ ] Strategy Tester run in **Every tick based on real ticks**, not "Open
      prices only" — grid and intrabar logic is meaningless at open prices.
- [ ] Run once on a symbol with non-zero stops level and integer lot steps
      (an index CFD) as well as on a forex pair.
- [ ] Restart test: attach, let it build state, remove the EA, re-attach, and
      confirm it recovers rather than duplicating.
