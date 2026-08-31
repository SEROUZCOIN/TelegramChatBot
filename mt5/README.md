# MetaTrader 5 bridge

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

## Also in this folder: `FibBot/`

[`FibBot/`](FibBot/README.md) is a standalone Expert Advisor that *finds* setups
rather than reporting yours. It detects non-repainting swing pivots, arms a
Fibonacci retracement setup only when independent non-Fibonacci confluence
agrees, waits for a confirmation close, then draws it and — if you switch
execution on — trades it.

It is unrelated to this bridge and talks to nothing: no API, no ingest key, no
WebRequest whitelisting. The two can run side by side on different symbols.

The method it implements, and the evidence for and against it, is
[`docs/education/fibonacci-retracement.md`](../docs/education/fibonacci-retracement.md).
