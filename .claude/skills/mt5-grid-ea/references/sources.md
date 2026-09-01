# Sources

Where the non-obvious claims in these two skills come from. Recorded so a future
reader can re-check them — broker behaviour and `Trade.mqh` internals both change
between terminal builds.

## Grid vs martingale risk

- [Building a Research-Grounded Grid EA in MQL5: Why Most Grid EAs Fail](https://www.mql5.com/en/articles/21833)
  — Taranto & Khan (2020) on the grid problem and the gambler's-ruin problem being
  mathematically distinct; the ~1,024 vs ~55 capital-unit comparison over ten
  adverse levels; win probability staying stable and then collapsing near a
  threshold; regime-adaptive grids with restartable cycles and equity safeguards.
- [Grid and martingale: what are they and how to use them?](https://www.mql5.com/en/articles/8390)
  — spacing vs lot-progression trade-off; exponential progression outperforming
  fixed volume on forex in the author's tests; the need for an explicit give-up
  point.
- [Developing a cross-platform grider EA (part III)](https://www.mql5.com/en/articles/7013)

## Order comments are not reliable identity

- [MQL5 forum: OrderComment bug](https://www.mql5.com/en/forum/150444) — brokers
  can change comments, including complete replacement.
- [How many letters does order comment support?](https://www.mql5.com/en/forum/464340)
  — ~31 characters, and broker additions (SL/TP text) consume part of the budget.
- [Can I modify position comment?](https://www.mql5.com/en/forum/252630) — comments
  are write-once at placement; code cannot change them.
- [Inherit or set new trade-comment on partially closed trade](https://www.mql5.com/en/forum/326381)
  — `PositionClosePartial` on a hedging account inherits SL/TP but **not** the
  comment; the new position's comment is empty.
- [Order Properties reference](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties)

## Partial fills and ticket identity

- [What happens with a partially filled order and its position ticket](https://www.mql5.com/en/forum/382788)
  — position and the remaining pending order can share a ticket; the position can
  close and reappear under the same ticket when the remainder fills.

## Stops level and freeze level

- [Purpose of SYMBOL_TRADE_FREEZE_LEVEL](https://www.mql5.com/en/forum/2574) —
  stops level governs *setting*, freeze level governs *modifying and deleting*.
- [MQL5 invalid stops](https://www.mql5.com/en/forum/393149) and
  [Automatic validation — invalid stops & prices](https://www.mql5.com/en/forum/476061)
  — a pending price inside either band is rejected; check both.
- [The checks a trading robot must pass before publication in the Market](https://www.mql5.com/en/articles/2555)
  — `CheckVolumeValue`, `CheckMoneyForTrade`, `CheckStopsLevel`; the basis for
  `mql5-trade-safety/references/preflight.md`.

## Filling modes

- [Order execution modes by price and volume](https://www.mql5.com/en/book/automation/experts/experts_execution_filling)
  — pending orders must use `ORDER_FILLING_RETURN` regardless of
  `SYMBOL_TRADE_EXEMODE`, because they fill later under the broker's rules at that
  time.
- [CTrade::SetTypeFillingBySymbol](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradesettypefillingbysymbol)
  — resolves the symbol's policy, choosing FOK when FOK and IOC are both allowed.
- [Unsupported filling mode (10030)](https://www.mql5.com/en/forum/221290)

## Margin

- [OrderCalcMargin reference](https://www.mql5.com/en/docs/trading/ordercalcmargin)
  — calculates for the given order "not taking into account current pending orders
  and open positions".
- [Margin calculation for a future order](https://www.mql5.com/en/book/automation/experts/experts_ordercalcmargin)
  and [Margin requirements](https://www.mql5.com/en/book/automation/symbols/symbols_margin)
  — forex pending orders usually require no margin; exchange tickers may.

## Performance

- [HistorySelect() slows down EA](https://www.mql5.com/en/forum/465370) — ~5–30 ms
  per call; several calls can consume seconds inside one `OnTick`; caching does not
  rescue it. Recompute on `OnTradeTransaction` instead.
- [Implementing a daily loss limit and drawdown circuit breaker in MQL5](https://www.mql5.com/en/articles/23732)
- [OrdersTotal in MQL5](https://www.mql5.com/en/forum/12807) — recompute when the
  count changes or on a new bar, not unconditionally per tick.

## State persistence

- [MQL5 Programming Basics: Global Variables of the Terminal](https://www.mql5.com/en/articles/1210)
  — persist across restarts in `profiles/gvariables.dat`; `double` only; expire
  after four weeks without access; flush with `GlobalVariablesFlush()` to avoid
  losing the last value on an unclean exit.
- [Keeping memory across restarts: EA state persistence using binary files](https://www.mql5.com/en/articles/22277)
- [Engineering a self-healing Expert Advisor in MQL5 (Part 1)](https://www.mql5.com/en/articles/22532)
  — reconstructing suspension state in `OnInit` so a recompile does not re-arm a
  stopped strategy.
