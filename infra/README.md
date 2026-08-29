# Infrastructure

## Local development

```bash
docker compose -f infra/docker-compose.yml up -d
```

Brings up PostgreSQL 16 (`:5432`), Redis 7 (`:6379`), and MinIO
(`:9000`, console `:9001`) as an S3 stand-in.

### Without Docker

The stack needs no container to run locally — Docker is a convenience:

```bash
# Debian/Ubuntu
apt-get install -y postgresql redis-server
service postgresql start && service redis-server start

su postgres -c "psql -c \"CREATE ROLE tsp LOGIN PASSWORD 'tsp' SUPERUSER;\""
su postgres -c "createdb -O tsp tsp"
```

Leave the S3 variables unset and `StorageService` falls back to writing under
`uploads/` on local disk, so image upload works with no object store at all.

## Production

| Piece | Suggested | Why |
|---|---|---|
| API | Fly.io, Railway, or a VPS behind Caddy | Long-lived process for the Telegram bot's polling loop |
| Database | Managed Postgres with PITR | The signal ledger is the product's credibility; losing it loses the record |
| Redis | Managed instance | Queues and rate limiting |
| Object storage | Cloudflare R2 | S3-compatible, no egress fees for chart images |
| Video | Cloudflare Stream | Signed URLs are what protect the paid library |
| Admin panel | Vercel | Static export, no server needed |

### Deploy

```bash
pnpm --filter @tsp/shared build
pnpm --filter @tsp/api build
pnpm --filter @tsp/api db:deploy   # migrate deploy — never `migrate dev` in production
node apps/api/dist/main.js
```

`migrate dev` is interactive and will offer to **reset the database** when it
finds drift. `migrate deploy` only applies pending migrations and never drops
anything, which is the only safe choice against real customer data.

Gate the deploy on readiness:

```bash
./preflight.sh --quiet || exit 1
```

It exits non-zero while any launch blocker stands, so a misconfigured
environment fails the pipeline instead of reaching customers.

### Run exactly one API instance while Telegram polls

`TELEGRAM_USE_POLLING=true` means the process long-polls Telegram for updates.
Two instances both poll, and **every subscriber receives every signal twice**.
Until you switch to webhooks, keep the API at one replica — this is the single
easiest way to embarrass yourself in front of paying subscribers.

### Health check

Point your load balancer at `GET /api/plans`. It is public, cheap, and touches
the database, so it fails when the thing that actually matters is broken —
unlike a static `/health` that returns 200 from a process with no database.

### Webhooks to register

| Provider | Endpoint |
|---|---|
| Stripe | `POST /api/webhooks/stripe` |
| NOWPayments | `POST /api/webhooks/crypto` |
| RevenueCat | `POST /api/webhooks/revenuecat` (only if a plan moves to IAP) |

Locally, forward Stripe with `stripe listen --forward-to localhost:3000/api/webhooks/stripe`.

### Telegram

`TELEGRAM_USE_POLLING=true` suits a single long-lived process. On a platform
that scales to several instances, switch to webhooks — otherwise every instance
polls and subscribers receive each message more than once.

## Backups

Back up Postgres. Everything that matters — the signal ledger, subscriptions,
payments, the audit trail — lives there. Media in R2 is replaceable; a signal's
history is not, and the published win rate is computed from it.
