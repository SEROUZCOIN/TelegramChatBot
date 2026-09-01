# MetaTrader 5

Two independent Expert Advisors. They share nothing but the folder.

| File | What it does | Trades? |
|---|---|---|
| `SignalBridge.mq5` | Publishes trades opened on your terminal to the platform as signals | No — reports only |
| `GridBot_2X_AutoUpdate.mq5` | Two-sided martingale grid with basket exits | Yes — this one places real orders |

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

A two-sided grid of limit orders with martingale sizing, ATR-adaptive spacing, an
EMA trend filter, and basket exits (fixed target, profit trail, emergency loss,
drawdown percent, daily loss lock). Unlike SignalBridge, **this EA places real
orders.** It requires a hedging account and refuses to start on a netting one.

It is kept here as the reference implementation the `mt5-grid-ea` skill is written
against, not as part of the signals platform — nothing in `apps/` or `packages/`
imports or depends on it.

### Read before running it

A full audit is in
[`.claude/skills/mt5-grid-ea/references/gridbot-2x-review.md`](../.claude/skills/mt5-grid-ea/references/gridbot-2x-review.md).
The two findings that decide whether it is safe to leave unattended:

- **Grid levels are identified by order comment.** Brokers may rewrite or truncate
  comments, and a partial close returns an empty one. When that happens the EA
  reads a level as empty and places a duplicate, which breaks both the lot ladder
  and the exposure cap.
- **The pause and daily-lock guards live only in memory.** After an emergency-loss
  stop or a daily loss lock, recompiling or restarting the terminal clears the
  flag and the EA resumes trading — the opposite of what the guard was for.

At the defaults the ladder is 0.01 / 0.02 / 0.04 / 0.08 / 0.16 = 0.31 lots, and
level five carries sixteen times the risk of level one. Raising
`InpLevelsPerSide` raises that exponentially; nothing in the file stops you.

### Setup

Copy to `MQL5/Experts/`, compile in MetaEditor (F7), attach to one chart. It
manages only the chart's symbol, and only orders carrying its own magic number,
so a second instance on another chart is safe.

Test it in the Strategy Tester on **Every tick based on real ticks** — a grid is
meaningless at open prices — and across a trending stretch rather than a calm
range.
