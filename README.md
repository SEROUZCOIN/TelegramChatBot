# Trading Signals + Academy Platform

A commercial trading-education platform: iOS and Android app, REST API,
admin control panel, and a Telegram subscriber bot.

| Piece | Stack |
|---|---|
| `apps/mobile` | Expo SDK 55 / React Native, expo-router |
| `apps/api` | NestJS + Fastify, Prisma, PostgreSQL, Redis |
| `apps/admin` | Next.js 15 App Router |
| `packages/shared` | Zod contracts, signal state machine, pip & R:R math |
| `mt5/` | MetaTrader 5 Expert Advisor bridge |

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

```bash
./start.sh
```

That is the whole thing. It installs packages, starts Postgres and Redis
(Docker if you have it, system services if you don't), runs migrations, seeds an
empty database, builds, and brings up the API and admin panel — then prints the
URLs and your login.

```
./start.sh --status     what is running
./start.sh --logs       tail the API log
./start.sh --stop       stop the API and admin panel
./start.sh --reset-db   drop and rebuild the database, then start
```

| | |
|---|---|
| Admin panel | http://localhost:3001 |
| API | http://localhost:3000/api |
| API docs | http://localhost:3000/api/docs |

The mobile app runs separately, since it needs a device or simulator:

```bash
pnpm --filter @tsp/mobile start          # Expo dev server — scan with Expo Go
pnpm --filter @tsp/mobile run android    # build to a connected device
```

<details>
<summary>Running the pieces by hand</summary>

```bash
pnpm install
docker compose -f infra/docker-compose.yml up -d   # or see infra/README.md
cp apps/api/.env.example apps/api/.env
pnpm --filter @tsp/shared build
pnpm --filter @tsp/api db:migrate
pnpm --filter @tsp/api db:seed     # prints the admin login and MT5 ingest key
pnpm --filter @tsp/api dev         # :3000
pnpm --filter @tsp/admin dev       # :3001
```
</details>

## Tests

```bash
pnpm --filter @tsp/shared test     # 47 — state machine, pip math, entitlements
pnpm --filter @tsp/api test        # 12 — entitlement grants, locked-payload leakage
```

The API suite runs against a real Postgres, because the behaviour worth testing
there is transactional: that an early renewal extends from the existing expiry
rather than today, that a one-time coaching purchase never lapses, and that a
locked signal's levels are *absent* from the serialised payload rather than
merely flagged.

## Before you submit to either store

Read [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) first. It is not optional
reading: the Google Play Financial Features Declaration blocks *all* releases
until it is filed, and the payment routing has a specific rationale under
Apple's guidelines that the code is built around.
