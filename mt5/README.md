# MetaTrader 5

Two independent Expert Advisors. They share nothing but the folder.

| File | What it does | Trades? |
|---|---|---|
| `SignalBridge.mq5` | Publishes trades opened on your terminal to the platform as signals | No — reports only |
| `GridBot_2X_AutoUpdate.mq5` | Self-configuring two-sided martingale grid | Yes — this one places real orders |

## SignalBridge

`SignalBridge.mq5` publishes trades opened on your MT5 terminal to the platform
as signals. It only reports — it never opens, modifies, or closes a position.

## Why this exists as a separate piece

The admin composer and this EA post the **same payload** (`signalInputSchema` in
`packages/shared`). Defining that contract before either caller existed is what
makes the auto-feed additive: turning it on adds a caller, it does not change
the server or the composer.

## Setup

1. **Allow the URL.** MetaTrader 5 → Tools → Options → Expert Advisors → tick
   *Allow WebRequest for listed URL* and add your API base URL. Skipping this is
   the single most common failure; every request returns `-1` with error `4014`.

2. **Create an ingest key.** Admin panel → Settings → MT5 bridge. The key is
   shown once and stored only as a hash. It authenticates the bridge alone, so
   revoking a compromised VPS does not touch any user's login.

3. **Compile and attach.** Copy the file to `MQL5/Experts/`, compile in
   MetaEditor (F7), and attach it to any one chart. It watches the whole
   terminal, not the chart it sits on, so one instance covers every symbol.

## Inputs

| Input | Meaning |
|---|---|
| `InpApiBaseUrl` | API base, e.g. `https://api.example.com/api` |
| `InpIngestKey` | The key from the admin panel |
| `InpMinPlan` | Tier that receives these signals (default `SIGNALS`) |
| `InpPublishNow` | Publish immediately, or leave as a draft to review first |
| `InpReportUpdates` | Report break-even moves as they happen |
| `InpPollSeconds` | Position poll interval |

## Behaviour worth knowing

- **Positions open when you attach the EA are adopted, not republished.** Only
  trades opened from that point on are sent.
- **A position without both a stop and a target is skipped.** The API requires
  both, and a signal without them is not actionable for a subscriber anyway.
- **Break-even detection.** When your stop moves to the entry price (within a
  20-point tolerance), the EA reports `MOVED_TO_BE`. This matters for accuracy
  rather than decoration: the platform scores a later stop-out *after* a
  break-even move as a scratch rather than a loss, so the published win rate
  stays honest.

---

## GridBot_2X_AutoUpdate

A two-sided grid of limit orders with martingale sizing and basket exits. Unlike
SignalBridge, **this EA places real orders.** It requires a hedging account and
refuses to start on a netting one.

It is kept here as the reference implementation the `mt5-grid-ea` skill is
written against, not as part of the signals platform — nothing in `apps/` or
`packages/` imports or depends on it.

### It configures itself

With `InpAutoConfigure` on (the default) you set a risk percentage and the EA
derives the rest at the start of every cycle:

| Derived | From |
|---|---|
| Grid distance | ATR, floored by the symbol's own spread, stops level and freeze level |
| Levels per side | The most the risk budget can survive |
| Base lot | Risk budget ÷ (step × tick value × ladder weight) |
| Multiplier | `InpPreferredMultiplier` if it fits, stepped down if it does not |
| Profit target, trail, emergency stop, exposure cap, daily loss limit | Percentages of equity |

The solver's contract: **if the ladder fills to its deepest level and price runs
one more step, the loss is about `InpRiskPercentPerCycle` of equity.** If no
shape satisfies that on this symbol — usually because the minimum lot is too
large for the account — the EA refuses to start and says so, rather than
quietly trading a riskier ladder than you asked for.

The chosen ladder is printed to the Experts log on every cycle, e.g.
`Ladder per side: 0.01 / 0.02 / 0.04 / 0.08 = 0.15 lots | step 420 points`.
Read it. It is the actual risk you are running.

Set `InpAutoConfigure` to false to drive the fixed inputs instead; every safety
mechanism behaves identically either way.

### What it will not do for you

Auto-sizing caps a loss; it does not remove one. This is still a martingale
grid — the deepest level of a five-level 2.0× ladder carries sixteen times the
risk of the first, and a grid's win rate stays high right up until it collapses.
A smooth backtest is the expected appearance of a system that has not yet met
its bad month, not evidence that it is safe.

Two guards matter most, and both now survive a restart: the emergency-loss pause
and the daily loss lock are written to terminal global variables and restored in
`OnInit`, so recompiling or restarting the terminal no longer re-arms an EA that
had stopped itself. If it starts paused, that is deliberate — delete its global
variables to clear it.

### Setup

Copy to `MQL5/Experts/`, compile in MetaEditor (F7), attach to one chart. It
manages only the chart's symbol, and only orders in its own magic-number range
(`InpMagicNumber + 1` through `+ 200`, one per side per level), so a second
instance on another chart is safe — give it a magic number at least 200 apart.

Test in the Strategy Tester on **Every tick based on real ticks** — a grid is
meaningless at open prices — and across a trending stretch rather than a calm
range.

### Design notes and audit

The full review, including what the v2.00 code got wrong and how v3.00 fixes
each item, is in `.claude/skills/mt5-grid-ea/references/gridbot-2x-review.md`.
