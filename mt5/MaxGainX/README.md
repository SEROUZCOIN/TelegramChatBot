# MaxGainX Spike Hunter v8.10

BUY-only Expert Advisor for **Weltrade SyntX MaxGainX 2000** (MetaTrader 5), rebuilt
from the v7 "FLIPPER / ASTRA" Fibonacci grid. Author credit: Monetraaa / Sirojiddin Sobitov.

> **Read this first — there is no "no-loss" EA.** SyntX prices are produced by an
> algorithm, and spike timing is random: a long wait since the last spike does not
> make the next one more likely. This EA does not predict spikes. It makes you
> choose your loss limits up front and then enforces them on every tick. Run it on
> a demo account for at least a week before using real money.

## What MaxGainX is

MaxGainX (and MaxPainX) were added to the Weltrade MT5 terminal on 18 August 2026 for
the SyntX World Cup. It is a higher-volatility member of the **GainX** family: price
drifts **down** in small ticks and jumps **up** in sudden spikes. Weltrade has not
published the exact spike frequency, so the EA measures it live and shows it on the
dashboard (`AVG EVERY … ticks`). Every other GainX symbol works too.

## How it trades

1. **Spike engine** (no indicators). At start the EA reads up to 20,000 recent ticks
   and learns the normal tick size. An UP tick at least `Spike sensitivity` times
   larger than normal counts as a spike. If large DOWN jumps dominate instead
   (a PainX-type feed), entries are blocked.
2. **A new Fibonacci on every spike.** Each spike draws fresh levels from the
   spike base to the spike top. As price drifts back down, a BUY opens just
   **before** price touches a level, starting with the first one (0.236). The
   level must not have been touched since the spike, and price must be falling.
   So a position is already open when the next spike comes. Until the EA has seen
   its first spike, it uses your v7 chart-pivot Fibonacci instead.
3. **Basket.** Up to `Maximum open BUY trades` positions. The first BUY of every
   new spike is always allowed, even with older trades still open lower down.
   Extra BUYs on the same spike must be at least `Grid gap %` below the lowest
   open BUY. **Lots never multiply**: the v7 ×1.5 ladder is gone.
4. **Spike banking.** When a spike prints and the basket is in net profit, the whole
   basket is closed. Otherwise, each profitable trade is partly closed and the rest is
   moved to break-even.
5. **Protection.** The basket stop, the stop-adding level, the daily loss and profit
   limits, the free-margin reserve, the spread filter, the cooldown after a basket
   stop, and the Algo Trading checks.

Following your choice, there is **no stop-loss per trade that can close at a loss**. The
basket stop and the daily loss limit are what cap losses. Break-even and trailing stops
are only ever placed **in profit**. If you want broker-side insurance for when the VPS
or terminal goes offline, set `Broker-side far stop-loss per trade` above 0.

## Installation

1. In MetaTrader 5 (Weltrade), open **File → Open Data Folder**, then go to `MQL5\Experts\`.
2. Copy the whole `MaxGainX` folder there.
3. Open `MaxGainX_SpikeHunter.mq5` in MetaEditor and press **F7** (Compile). You should
   get 0 errors and 0 warnings. If you get any, send me the exact lines.
4. Open a **MaxGainX 2000** chart. **M1** is recommended, because it gives the most
   swings; M5 gives fewer, larger swings.
5. Drag the EA onto the chart, tick **Allow Algo Trading**, and turn on the **Algo
   Trading** button in the toolbar.
6. The account must be a **hedging** account. The EA refuses to start on netting.

Telegram (optional): set `Telegram messages = true`, fill in the bot token and chat id,
and add `https://api.telegram.org` under **Tools → Options → Expert Advisors → Allow
WebRequest for listed URL**. Never paste your token into chats or code.

## Inputs (plain English)

| Group | Input | Default | What it does |
|---|---|---|---|
| Main | Lot mode | Risk % | `Risk %` sizes each trade from equity; `Fixed lot` uses the fixed size |
| | Risk % per trade | 1.0 | % of equity lost if price falls one full swing after entry |
| | Fixed lot | 0.01 | Used when Lot mode = Fixed lot |
| | Maximum lot | 1.0 | Hard cap per trade |
| | Use broker minimum lot | true | If the risk lot is below the broker minimum, trade the minimum. The dashboard shows `MIN` |
| | Maximum open BUY trades | 5 | Basket size |
| | Magic number | 20260818 | Use a different number on every chart |
| | Trade only symbols containing | GainX | Safety check against attaching to the wrong chart. Leave empty to allow any symbol |
| Entry | Draw Fibonacci on | Every spike | `Every spike` (base → top of the last spike) or `Confirmed chart pivots` (v7 behaviour) |
| | Entry zone | 0.236 | First level that may trigger. 0.236 = right after each spike; 0.5 or 0.618 = deeper, fewer trades |
| | Pre-touch window | 5 % | How close above a level (as % of the swing) the entry fires |
| | Grid gap | 10 % | Minimum distance below the lowest open BUY |
| | First BUY of every new spike | true | The first trade after each spike ignores the grid gap, so every spike gets a position |
| | Spike sensitivity | 8 | Raise it if `SPIKES SEEN` counts normal ticks; lower it if real spikes are missed |
| | Warm-up ticks | 20000 | History ticks used to learn the symbol (0 = learn from 300 live ticks) |
| | Maximum spread | 0 = auto | Auto = 15 % of the 14-bar average range |
| Exit | When a spike prints | Bank basket | `Bank basket`, `Partial + break-even`, or `Hold` |
| | Partial close % | 50 | Share of each profitable trade closed on a spike. Trades too small to split are closed in full |
| | Break-even trigger | 0 = auto | Auto = one average bar range. −1 = off |
| | Trailing start / distance | 0 = auto | Auto = 1 bar range / 0.5 bar range. Start −1 = off |
| | Basket take-profit % | 0 = off | Close the basket at this profit (% of balance) |
| Protection | Basket stop % | 5 | **Closes everything** at this basket loss (% of balance) |
| | Stop-adding level % | 3 | No new BUYs while the basket loss is this deep |
| | Daily loss limit % | 5 | Closes everything and stops trading until the next server day |
| | Daily profit target % | 0 = off | No new trades after the target. Open trades are still managed |
| | Free margin reserve % | 30 | Always keep this share of equity free |
| | Cooldown minutes | 30 | Wait after a basket stop before trading again |
| | Broker-side far stop-loss | 0 = off | Optional insurance for when the terminal is offline |
| | Maximum slippage | 0 = auto | Auto = 2× the current spread, at least 10 points |
| Time | Trading hours | off | Server time. SyntX trades 24/7. There is no news filter because synthetic indices don't react to news |
| Alerts | Pop-up / Push / Telegram | on / off / off | Pop-ups only for important events (basket stop, daily limits) |
| Dashboard | Dashboard, theme, FX, levels, spike marks | on | The FX pulse is cosmetic only and never affects trading |

## Dashboard

- **Status bar.** The light pulses when FX is on, and the colour shows the state: neon =
  scanning, green = basket active, gold = paused or target hit, red = blocked.
- **01 Spike engine.** The spike threshold, the normal tick size, spikes seen, the
  average interval, the last spike, and ticks since the last spike. The
  interval-based numbers are information only; they do not predict the next spike.
- **02 Fibonacci.** Whether the levels come from the last spike or chart pivots,
  the swing low and high, the current retracement bar with the gold entry-zone
  marker, and the next level that can trigger.
- **03 Basket.** Open trades, lots, floating P/L, the lowest entry, how many trades
  are protected in profit, the basket-stop amount, and the next lot size.
- **04 Risk guard.** Balance, equity, today's P/L against the daily limit, spread
  against its limit, and cooldown or halt state.
- **Buttons.** `PAUSE NEW ENTRIES` (open trades are still managed) and `CLOSE ALL TRADES`,
  which needs a second click within 5 seconds to confirm.

## What changed from v7

| v7 | v8 |
|---|---|
| Lots ×1.5 after every BUY (martingale) | Risk % or fixed lot. Never multiplies |
| No stop at all, only profit trailing | Basket stop, stop-adding level, daily loss/profit limits, cooldown |
| 20 BUYs allowed | 5 by default |
| `CountBuys()` computed the lowest entry but never used it, so BUYs could stack at almost the same price | Grid gap below the lowest BUY is enforced |
| Any Fibonacci level could trigger, including the 0 level (the swing top) | Only levels at or below the Entry zone (0.236 by default) |
| Fibonacci only from chart pivots, confirmed 3 candles late | v8.10: a new Fibonacci from every spike, with a BUY before the first level is touched |
| No spike awareness | Tick spike engine, spike banking, and a direction safety check |
| Dashboard fully rebuilt on every tick | Redrawn on a 500 ms timer and skipped entirely in non-visual testing |
| `#property strict` (an MQL4 leftover) | Removed |

Kept from v7: the Fibonacci pivot engine, the pre-touch entry rule, level reservations
that survive a restart, the single-instance lock, the free-margin guard, the broker
volume-limit check, the dark chart theme, and the pause button.

## Strategy Tester guide

1. Symbol **MaxGainX 2000**, period **M1**, modelling **"Every tick based on real ticks"**.
   The spike engine needs real ticks; "1 minute OHLC" invents ticks and gives
   misleading spike counts.
2. Deposit the size you will really trade, with the same leverage as your account.
3. Test at least a few weeks, as far as the MaxGainX history allows (it has existed
   since 18 Aug 2026). Then forward-test on demo.
4. Run once in **visual mode** to check the dashboard, the spike arrows and the Fibonacci lines.
5. Judge the result by **equity drawdown** and the **largest loss**, not the win rate. A
   basket strategy can win for weeks and then give it back in one basket stop.
6. Optimisation criterion: **Custom max**. `OnTester` returns profit × profit factor ÷
   equity drawdown %, and rejects runs with fewer than 30 trades.

Useful ranges to optimise, a few at a time:

| Input | Range |
|---|---|
| Entry zone | 0.236 – 0.618 |
| Spike sensitivity | 6 – 14 |
| Grid gap % | 5 – 20 |
| Pre-touch window % | 2 – 8 |
| Basket stop % | 3 – 8 |
| Maximum open BUY trades | 3 – 7 |

Prefer settings that stay profitable across a whole range of values over one "best" value.
Always re-check the winning settings on a period the optimiser didn't see
(walk-forward).

## VPS notes

- One chart per symbol/magic. A second copy with the same magic refuses to start.
- The pause state, cooldown, daily baseline, daily halt and used Fibonacci levels
  are stored in terminal global variables, so a restart continues where it stopped.
- Losses are capped by the EA itself, so it must be running. Use a VPS, or set the
  broker-side far stop-loss as insurance.

## Ideas for a later version

- An on-chart settings editor (change risk and entry zone without reopening inputs).
- A walk-forward report exported to CSV from `OnTester`.
- Reporting to the platform's `SignalBridge.mq5`. It only publishes positions that have
  both SL and TP, which basket trades don't have by design.
