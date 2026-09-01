# Diagnosing MT5 trade retcodes

Read the retcode, the retcode description, and the broker comment together.
`CTrade` exposes all three:

```cpp
PrintFormat("%s failed. retcode=%u (%s) broker=%s",
            action, trade.ResultRetcode(),
            trade.ResultRetcodeDescription(), trade.ResultComment());
```

| Retcode | Name | Usual cause in an EA | First thing to check |
|---|---|---|---|
| 10004 | REQUOTE | Price moved between quote and send | Raise deviation; use limit orders |
| 10006 | REJECT | Broker-side rejection | Read `ResultComment()` — it names the reason |
| 10013 | INVALID | Malformed request | Unnormalised price, zero volume, wrong order type for the side |
| 10014 | INVALID_VOLUME | Volume not a multiple of `SYMBOL_VOLUME_STEP`, or outside min/max | Re-run volume normalisation; print min/step/max |
| 10015 | INVALID_PRICE | Price not on a `SYMBOL_TRADE_TICK_SIZE` boundary | Round to tick size, then `NormalizeDouble` to `SYMBOL_DIGITS` |
| 10016 | INVALID_STOPS | Price/SL/TP inside `SYMBOL_TRADE_STOPS_LEVEL`, or a modify inside `SYMBOL_TRADE_FREEZE_LEVEL` | Check **both** levels; they are often 0 on forex and non-zero on indices |
| 10018 | MARKET_CLOSED | Outside the symbol's session | `SYMBOL_TRADE_MODE`, session times |
| 10019 | NO_MONEY | Insufficient free margin | `OrderCalcMargin` ignores existing exposure — budget for the whole ladder |
| 10024 | TOO_MANY_REQUESTS | Bulk delete/replace on every tick | Move rebuilds to a timer or new bar; add a cooldown |
| 10027 | CLIENT_DISABLES_AT | Algo trading off in the terminal | `TERMINAL_TRADE_ALLOWED`, `MQL_TRADE_ALLOWED` |
| 10030 | INVALID_FILL | Filling policy the symbol or order type does not accept | Pending orders need `ORDER_FILLING_RETURN`, not FOK/IOC |
| 10036 | POSITION_CLOSED | Position already gone | Stale ticket — re-select before acting |

## Reading a partial fill

`TRADE_RETCODE_DONE_PARTIAL` (10009 family) means the volume you got is not the
volume you asked for. On a partially filled pending order the position and the
still-live remainder of the order can carry the same ticket, and the position can
close and then reappear under that same ticket when the remainder fills.

Consequences to design for:

- Ticket identity alone does not prove "this is the same trade I saw last pass".
- Volume accounting must read `ORDER_VOLUME_CURRENT` (the remaining volume), not
  the original request.
- A slot-based EA must not treat "a position exists for this slot" as "this slot
  is fully consumed".

## When the same code works on one symbol and fails on another

Almost always one of these differs between the two symbols:

- `SYMBOL_TRADE_STOPS_LEVEL` / `SYMBOL_TRADE_FREEZE_LEVEL` — zero on many forex
  pairs, non-zero on indices, metals, and exchange instruments.
- `SYMBOL_VOLUME_MIN` / `SYMBOL_VOLUME_STEP` — 0.01/0.01 on forex, 1/1 on many
  index CFDs, which makes small martingale steps unrepresentable.
- `SYMBOL_TRADE_TICK_SIZE` vs `_Point` — equal on forex, different elsewhere.
- `SYMBOL_TRADE_EXEMODE` and the allowed filling policies.
- `SYMBOL_FILLING_MODE` bitmask — a symbol may allow only one policy.

Print all of these once in `OnInit`. It turns a class of mystery rejections into
a one-line diagnosis.
