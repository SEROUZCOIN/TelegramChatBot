# Grid Fibonacci Pro — MetaTrader 5 Expert Advisor

A grid EA whose ladder is bounded by market structure rather than by a level
count. It trades one setup: a pullback into the Fibonacci retracement of a
confirmed impulse leg, in a market whose regime says that pullback is worth
buying, with stops at structural invalidation and targets on the extension
ladder.

```
mt5/GridFibonacciEA/          ← copy this whole folder into MQL5\Experts\
   GridFibonacciEA.mq5        events, wiring, input validation
   Config.mqh                 every input, enum, colour and dimension
   State.mqh                  runtime state + the grid level collection
   Utils.mqh                  normalisation, broker limits, portfolio queries
   Fibonacci.mqh              impulse-leg detection and fib geometry
   Signals.mqh                the moving-average engine and regime filter
   Execution.mqh              every OrderSend in the project, in one place
   Risk.mqh                   position sizing and account protection
   Grid.mqh                   the cycle engine
   Telemetry.mqh              alerts, Telegram, dashboard JSON
   Panel.mqh                  the on-chart neon HUD and structure drawing
```

Includes are quoted and relative, so the folder compiles from any location.
Angle brackets appear only for `<Trade\Trade.mqh>` and `<Arrays\ArrayObj.mqh>`,
which exist in every terminal.

## The trading logic

**1 · Regime.** Three moving averages (21/55/200 by default) must be strictly
stacked; the 200's slope, normalised by ATR so one threshold works on EURUSD
and on XAUUSD alike, must exceed `InpMinSlopeAtr`; ADX must clear
`InpAdxTrendMin`; and the higher timeframe must agree. All four give
`TREND UP`/`TREND DOWN`. ADX under `InpAdxRangeMax` gives `RANGE`. Anything
else is `CHOP`, and chop opens nothing at all.

**2 · Structure.** The EA walks back for the most recent *confirmed* pivot —
`InpPivotStrength` bars on each side, so it can only be judged after the fact
and never repaints — then takes the opposing extreme between that pivot and
the lookback horizon as the leg origin. That yields the largest leg ending at
the same swing, which is the leg a discretionary trader would actually draw.
Legs smaller than `InpMinSwingAtr × ATR` are rejected: their fib levels sit
inside the noise band.

**3 · Entry.** Price must trade into the 0.382–0.786 retracement window and
confirm — a close back through the fast MA, a rejection wick, or both. In a
range the EA additionally insists on the deeper half of the window, because a
shallow pullback inside a range is noise rather than a discount.

**4 · The grid.** Additional levels go on the Fibonacci ladder of that same
leg (`SPACING_FIB_LEG`), or at ATR distances widened by the Fibonacci sequence
1 · 1.618 · 2.618 · 4.236 (`SPACING_ATR_FIB`, the default). The widening is the
point: equally spaced ladders fill completely inside a single impulse, which is
how grids die. Three hard limits apply to every add — one fill per bar, the
total-risk budget, and **never past the structural stop**. When the next step
would land at or beyond invalidation the ladder simply closes; the panel says
`ladder closed`.

**5 · Exit.** Partial closes at the 1.272 and 1.618 extensions, the remainder
running to 2.618, plus a basket money target, break-even on the *basket
average* (the only meaningful reference once the ladder has more than one
step), and ATR or fib-step trailing. Every position also carries the real stop
and the far target broker-side, so a dead terminal still leaves the basket
bracketed.

**6 · Survival.** Cycle loss ceiling, daily loss limit, daily profit target,
total drawdown from the equity high-water mark, an absolute equity floor,
spread and session filters, and a panic halt on the panel.

## Setup

**[INSTALL.md](INSTALL.md) is the step-by-step version, with screenshots of the
menus and a troubleshooting table.** The short form:

1. Copy the `GridFibonacciEA` folder into `MQL5\Experts\` (MT5 → **File → Open
   Data Folder**). All eleven files must stay together.
2. Open `GridFibonacciEA.mq5` in MetaEditor and press **F7**.
3. Attach it to one chart. It trades that chart's symbol only — run one
   instance per symbol, each with its own magic number.
4. For Telegram or the Python dashboard: **Tools → Options → Expert Advisors →
   Allow WebRequest for listed URL**, and add `https://api.telegram.org` and
   your dashboard URL. Without this every request returns −1 with error 4014.

Works on hedging and netting accounts. On netting the ladder shares one
aggregate position, and the weighted average the server maintains is the same
number the EA computes, so management is identical either way.

## Inputs that decide the character of the system

| Input | Default | What it changes |
|---|---|---|
| `InpGridSpacing` | `SPACING_ATR_FIB` | `SPACING_FIB_LEG` puts every add on a fib level of the leg — fewer, better-located adds. The ATR models widen with distance. `SPACING_FIXED_POINTS` is the classic equal-step grid, and the most fragile. |
| `InpLotProgression` | `PROG_FLAT` | `PROG_FLAT` is the survivable default. `PROG_FIBONACCI` and `PROG_GEOMETRIC` are martingale: they raise the win rate and the size of the eventual loss together. |
| `InpGridMaxLevels` | 6 | The ladder cap. The risk budget usually binds first. |
| `InpMaxTotalRiskPct` | 6.0 | The whole basket's theoretical risk. The base lot is divided by the ladder's total progression units so the *finished* ladder fits this budget, not just the first entry. |
| `InpCycleMaxLossPct` | 4.0 | Closes the cycle before the structural stops are reached, if the basket bleeds. |
| `InpRegimePolicy` | `REGIME_BOTH` | Restrict to trends only if you want fewer, cleaner cycles. |
| `InpEntryConfirm` | `CONFIRM_MA_RECLAIM` | `CONFIRM_BOTH` trades far less and misses fewer knife-catches. |

Every switchable input is copied into runtime state at `OnInit`; the panel's
buttons and the protection breaches flip the state, never the input. That is
why a "TRADING OFF" click actually stops trading rather than appearing to.

## The on-chart panel

Dark, neon-cyan and gold, docked left by default (`InpPanelRight` docks it
right and it follows the chart width). It shows the regime block, the fib
structure and where price sits inside it, the live cycle with its ladder and
basket levels, the account with drawdown against its limit, and the cycle
statistics. Four controls: **TRADING ON/OFF**, **GRID ON/OFF**, **CLOSE
BASKET**, **PANIC HALT** (which also clears a halt when pressed again).

The chart itself gets the impulse leg, the retracement ladder with 0.5 and
0.618 highlighted, the extension targets, the entry zone as a filled band, and
every grid level with its lot size, the pending next step, the basket stop and
the basket average.

## Strategy Tester

- **Modelling**: "Every tick based on real ticks" for a verdict you can trust.
  "1 minute OHLC" is acceptable while exploring; "Open prices only" is *not* —
  the grid adds, the partials and the trailing all read intrabar price.
- **Period**: at least two years, and make sure it contains both a strong trend
  and a long range. A grid EA tested only on a range looks extraordinary.
- **Deposit and leverage**: test the small deposit too. Below a certain equity
  the risk-sized lot falls under the broker minimum and the EA correctly opens
  nothing — better to discover that in the tester.
- **Custom criterion**: `OnTester` returns `profit × profit-factor ×
  recovery-factor ÷ drawdown²`, and returns 0 under 40 trades or on a losing
  pass. Select **Custom max** in the tester. Optimising a grid on net profit
  alone reliably converges on the deepest, most fragile ladder ever tested.

Optimise in this order, and re-verify out of sample after each stage:

1. Structure — `InpPivotStrength`, `InpSwingLookback`, `InpMinSwingAtr`.
2. Regime — `InpAdxTrendMin`, `InpMinSlopeAtr`, `InpMaSlow`.
3. Entry window — `InpEntryFibMin`/`InpEntryFibMax`, `InpEntryConfirm`.
4. Grid — `InpGridBaseAtr`, `InpGridMaxLevels`, `InpGridSpacing`.
5. Exits — `InpTp1ClosePct`, `InpTp2ClosePct`, `InpBasketTpMode`.

Leave risk and protection inputs out of the optimiser entirely. They are
policy, not parameters, and optimising them just means selecting the run that
happened not to hit the limit.

## Known limits

- **One cycle at a time**, in one direction, per symbol and magic. Simultaneous
  opposing baskets are deliberately not supported: they make exposure hard to
  bound, which is the failure mode this EA is built to avoid.
- **An adopted basket is managed, never extended.** After a restart the EA
  reconstructs the cycle from live positions and runs it to its exit, but will
  not add to it — the anchor leg that justified the ladder is gone.
- **A basket at the broker minimum cannot be partially closed.** TP1 and TP2
  are marked done and the position runs to the final target; the log says so.
- `InpNewsTimes` is a manual list, not a calendar feed.

## Suggested next versions

- A calendar-driven news filter through `WebRequest` instead of the manual list.
- Multi-symbol operation from one chart, with a correlation cap so three
  correlated baskets are not really one leveraged basket.
- Cycle state persisted to file so a restart restores targets and partial
  progress exactly, not just the positions.
- Walk-forward automation via `terminal64.exe /config:tester.ini`.
- An ONNX regime classifier to replace the ADX/slope heuristic, scored against
  it out of sample before being trusted.
