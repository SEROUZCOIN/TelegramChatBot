# Trading Signals + Academy Platform

A commercial trading-education platform: iOS and Android app, REST API,
admin control panel, and a Telegram subscriber bot.

| Piece | Stack |
|---|---|
| `apps/mobile` | Expo SDK 55 / React Native, expo-router |
| `apps/api` | NestJS + Fastify, Prisma, PostgreSQL, Redis |
| `apps/admin` | Next.js 15 App Router |
| `packages/shared` | Zod contracts, signal state machine, pip & R:R math |
| `mt5/` | MetaTrader 5: the signal bridge, and the Grid Fibonacci EA |
| `tools/dashboard` | Dash + Plotly 3D control room for the EA |

## Trading automation

`mt5/GridFibonacciEA/` is a standalone Expert Advisor — a grid whose ladder is
bounded by market structure rather than by a level count. It enters on
Fibonacci retracements of confirmed impulse legs, gated by a triple moving
average stack, an ATR-normalised slope and ADX; stops sit at structural
invalidation and targets on the 1.272 / 1.618 / 2.618 extensions.

`tools/dashboard/` renders it live in 3D: the grid ladder, a basket P/L surface
over price move and ladder depth, and the equity path plotted against its own
drawdown. It reads the EA's telemetry over HTTP, a local MT5 terminal directly,
or a built-in demo feed.

```bash
cd tools/dashboard && pip install -r requirements.txt && python app.py --demo
```

Neither piece touches the signals platform below — they share the repository,
not a runtime.

## Plans

| Plan | Price | Includes |
|---|---|---|
| Signals | $75 / month | Live signals with entry, TP1–TP3, SL, break-even |
| Normal | $100 / month | Signals + the full recorded video library |
| Pro | $1,500 one-time | Normal + live one-to-one mentoring |
| Ultra | $5,000 one-time | Pro + the beginner-to-professional curriculum |

## Two ideas hold the system together

**One definition of a signal.** `packages/shared` owns the signal schema, its
state machine, and its pip/risk-reward math. The API, the admin panel, the
mobile app, and the Telegram bot all import it, so a signal cannot mean two
different things on two different surfaces — and the MT5 bridge posts the same
payload the admin composer does.

**Status is derived, never stored.** A signal's status is a fold over its
append-only update ledger (`resolveStatus`). The badge a subscriber sees and the
timeline they read cannot drift apart, which is what makes the published win
rate trustworthy. A stop-out *after* the stop was moved to break-even is scored
as a scratch, not a loss — see `packages/shared/src/signal-state.ts`.

## Getting started

You need Node.js 20+ and nothing else. The database is a free hosted Postgres
you paste a URL for; the launcher asks you for it and remembers it.

```bash
node run.js
```

That installs packages (pnpm arrives through corepack, which ships inside
Node), sets up the database, builds, and starts the API and admin panel.

```
node run.js --status     what is running
node run.js --logs       follow the API log
node run.js --stop       stop the servers
node run.js --reset-db   drop and rebuild the database, then start
```

| | |
|---|---|
| Admin panel | http://localhost:3001 |
| API | http://localhost:3000/api |
| API docs | http://localhost:3000/api/docs |

**On Windows?** [`docs/WINDOWS.md`](docs/WINDOWS.md) walks through it from
installing Node, written for a first dev setup.

The mobile app runs separately, since it needs a device or simulator:

```bash
pnpm --filter @tsp/mobile start          # Expo dev server — scan with Expo Go
pnpm --filter @tsp/mobile run android    # build to a connected device
```

<details>
<summary>Running your own Postgres instead</summary>

Set `DATABASE_URL` in `apps/api/.env` to any Postgres and the launcher will use
it. `infra/docker-compose.yml` brings one up locally if you have Docker, and
`infra/README.md` covers installing it directly.

</details>

## Tests

```bash
pnpm --filter @tsp/shared test     # 47 — state machine, pip math, entitlements
pnpm --filter @tsp/api test        # 12 — entitlement grants, locked-payload leakage
node --test "test/**/*.test.mjs"   #  7 — the launcher's Windows branches
```

The launcher tests force `process.platform` to `win32` so the Windows-only code
paths can be checked from any machine. They matter because those branches fail
silently elsewhere: without `shell: true` Node cannot find `pnpm.cmd`, and
killing a bare pid rather than the process tree leaves a server running while
the launcher reports success.

The API suite runs against a real Postgres, because the behaviour worth testing
there is transactional: that an early renewal extends from the existing expiry
rather than today, that a one-time coaching purchase never lapses, and that a
locked signal's levels are *absent* from the serialised payload rather than
merely flagged.

## Going live

```bash
./preflight.sh
```

Checks every credential and reports what is ready, what is missing, and what
each gap costs you — making a real authenticated call to each provider, so a
mistyped key reads as broken rather than green. Non-zero exit while any launch
blocker stands, so it can gate a deploy.

[`docs/GO-LIVE.md`](docs/GO-LIVE.md) is the ordered runbook that goes with it.

## Before you submit to either store

Read [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) first. It is not optional
reading: the Google Play Financial Features Declaration blocks *all* releases
until it is filed, and the payment routing has a specific rationale under
Apple's guidelines that the code is built around.
