#!/usr/bin/env bash
#
# Start the whole platform locally: database, cache, API, admin panel.
#
#   ./start.sh              start everything
#   ./start.sh --stop       stop the API and admin panel
#   ./start.sh --status     show what is running
#   ./start.sh --logs       tail the API log
#   ./start.sh --reset-db   drop and rebuild the database, then start
#
# Postgres and Redis come from Docker when it is available and from local
# system services otherwise, so this works on a machine without Docker.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/.logs"
mkdir -p "$LOG_DIR"

API_PORT=3000
ADMIN_PORT=3001

# Narrow enough not to match an unrelated process, and Next renames itself to
# "next-server" once started, so its own name is what to look for.
API_PATTERN="node dist/main.js"
ADMIN_PATTERN="next-server"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'
red=$'\033[31m'; blue=$'\033[34m'; reset=$'\033[0m'

step() { printf '%s==>%s %s\n' "$blue$bold" "$reset" "$1"; }
ok()   { printf '    %s✓%s %s\n' "$green" "$reset" "$1"; }
warn() { printf '    %s!%s %s\n' "$yellow" "$reset" "$1"; }
die()  { printf '    %s✗%s %s\n' "$red" "$reset" "$1"; exit 1; }

port_busy() { curl -sf -o /dev/null "http://localhost:$1" 2>/dev/null; }

# Wait for a command to succeed, up to N seconds.
wait_for() {
  local what="$1" seconds="$2"; shift 2
  for _ in $(seq 1 "$seconds"); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

# Whatever is listening on the port is the process to stop.
#
# The alternatives are both unreliable here: `pgrep -f` can match the calling
# shell's own command line and kill it, Next renames its process to
# "next-server" so no sensible pattern finds it, and a PID recorded at launch
# is the wrapper's rather than the server's because setsid forks. The listening
# socket is the one thing that is unambiguously the running server.
API_PID_FILE="$LOG_DIR/api.pid"
ADMIN_PID_FILE="$LOG_DIR/admin.pid"

# Finding the server process is fiddlier than it looks, so all three routes are
# used, in order of reliability:
#
#   * the PID recorded once the server answered — captured after startup rather
#     than from `$!`, because setsid forks and would report the wrapper's PID;
#   * whatever holds the listening socket — right when it works, but lsof
#     cannot see every socket in every sandbox;
#   * a process-name match, narrow enough not to match a shell that merely
#     mentions the pattern, and never this script or its parent.
listener_pid() {
  command -v lsof >/dev/null && lsof -ti "tcp:$1" -sTCP:LISTEN 2>/dev/null | head -1
}

named_pid() {
  pgrep -f "$1" 2>/dev/null | grep -vx -e "$$" -e "$PPID" | head -1
}

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# Resolve the running server's PID, whichever way works on this machine.
resolve_pid() {
  local port="$1" pid_file="$2" pattern="$3" pid=""
  [ -f "$pid_file" ] && pid="$(cat "$pid_file" 2>/dev/null || true)"
  alive "$pid" || pid="$(listener_pid "$port")"
  alive "$pid" || pid="$(named_pid "$pattern")"
  alive "$pid" && printf '%s' "$pid"
}

stop_one() {
  local name="$1" port="$2" pid_file="$3" pattern="$4" pid=""

  pid="$(resolve_pid "$port" "$pid_file" "$pattern")"
  rm -f "$pid_file"
  alive "$pid" || return 1

  kill "$pid" 2>/dev/null || return 1
  for _ in 1 2 3 4 5; do
    sleep 1
    alive "$pid" || { ok "stopped $name"; return 0; }
  done

  kill -9 "$pid" 2>/dev/null || true
  sleep 1
  ok "stopped $name (forced)"
}

stop_services() {
  step "Stopping API and admin panel"
  local stopped=1
  stop_one api "$API_PORT" "$API_PID_FILE" "$API_PATTERN" && stopped=0
  stop_one admin "$ADMIN_PORT" "$ADMIN_PID_FILE" "$ADMIN_PATTERN" && stopped=0
  [ "$stopped" = 0 ] || warn "nothing was running"
  printf '%sPostgres and Redis were left running.%s\n' "$dim" "$reset"
}

show_status() {
  step "Status"
  pg_isready -q 2>/dev/null   && ok "postgres  :5432" || warn "postgres  :5432  down"
  redis-cli ping >/dev/null 2>&1 && ok "redis     :6379" || warn "redis     :6379  down"
  port_busy "$API_PORT/api/plans" && ok "api       :$API_PORT" || warn "api       :$API_PORT  down"
  port_busy "$ADMIN_PORT"         && ok "admin     :$ADMIN_PORT" || warn "admin     :$ADMIN_PORT  down"
}

case "${1:-}" in
  --stop)   stop_services; exit 0 ;;
  --status) show_status; exit 0 ;;
  --logs)   tail -f "$LOG_DIR/api.log" ;;
esac

RESET_DB=0
[ "${1:-}" = "--reset-db" ] && RESET_DB=1

# ---------------------------------------------------------------- dependencies
step "Checking dependencies"
command -v node >/dev/null || die "node is not installed (need v20+)"
command -v pnpm >/dev/null || die "pnpm is not installed — run: npm i -g pnpm"
command -v lsof >/dev/null || warn "lsof is missing — ./start.sh --stop will not work"
ok "node $(node -v), pnpm $(pnpm -v)"

if [ ! -d node_modules ]; then
  step "Installing packages (first run, this takes a minute)"
  pnpm install
fi

# ------------------------------------------------------------ postgres + redis
step "Starting Postgres and Redis"

if docker info >/dev/null 2>&1 && [ -f infra/docker-compose.yml ]; then
  docker compose -f infra/docker-compose.yml up -d >/dev/null 2>&1 \
    && ok "containers up" \
    || warn "docker compose failed, falling back to system services"
fi

if ! pg_isready -q 2>/dev/null; then
  if command -v pg_isready >/dev/null; then
    service postgresql start >/dev/null 2>&1 || sudo service postgresql start >/dev/null 2>&1 || true
  else
    die "Postgres is not installed. See infra/README.md for the no-Docker setup."
  fi
fi
wait_for postgres 30 pg_isready -q || die "Postgres did not come up"
ok "postgres ready"

if ! redis-cli ping >/dev/null 2>&1; then
  service redis-server start >/dev/null 2>&1 || sudo service redis-server start >/dev/null 2>&1 || true
fi
redis-cli ping >/dev/null 2>&1 && ok "redis ready" \
  || warn "redis is not running — queues are unused in dev, continuing"

# The app's own role and database, created once.
if ! su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='tsp'\"" 2>/dev/null | grep -q 1; then
  su postgres -c "psql -c \"CREATE ROLE tsp LOGIN PASSWORD 'tsp' SUPERUSER;\"" >/dev/null 2>&1 \
    && ok "created role 'tsp'" || true
fi
if ! su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='tsp'\"" 2>/dev/null | grep -q 1; then
  su postgres -c "createdb -O tsp tsp" >/dev/null 2>&1 && ok "created database 'tsp'" || true
fi

# ------------------------------------------------------------------ environment
if [ ! -f apps/api/.env ]; then
  step "Creating apps/api/.env from the example"
  cp apps/api/.env.example apps/api/.env
  warn "using development defaults — set JWT_SECRET before deploying anywhere"
fi

# ----------------------------------------------------------------------- build
step "Building"
pnpm --filter @tsp/shared build >/dev/null && ok "shared contracts"
pnpm --filter @tsp/api exec prisma generate >/dev/null 2>&1 && ok "prisma client"

if [ "$RESET_DB" = 1 ]; then
  warn "resetting the database — all local data will be lost"
  pnpm --filter @tsp/api exec prisma migrate reset --force --skip-seed >/dev/null 2>&1
fi

pnpm --filter @tsp/api exec prisma migrate deploy >/dev/null 2>&1 && ok "migrations applied"

# Seed only an empty database, so restarting never clobbers your own data.
PLAN_COUNT=$(PGPASSWORD=tsp psql -h 127.0.0.1 -U tsp -d tsp -tAc \
  "SELECT count(*) FROM plans" 2>/dev/null || echo 0)
if [ "${PLAN_COUNT:-0}" = "0" ]; then
  step "Seeding (first run)"
  pnpm --filter @tsp/api db:seed 2>&1 | sed 's/^/    /'
else
  ok "database already seeded ($PLAN_COUNT plans)"
fi

pnpm --filter @tsp/api build >/dev/null && ok "api"

if [ ! -d apps/admin/.next ]; then
  step "Building the admin panel (first run)"
  pnpm --filter @tsp/admin build >/dev/null 2>&1
fi
ok "admin panel"

# --------------------------------------------------------------------- servers
step "Starting servers"

# Free the ports first so a restart never silently leaves the old build serving.
stop_one api "$API_PORT" "$API_PID_FILE" "$API_PATTERN" >/dev/null 2>&1 || true
stop_one admin "$ADMIN_PORT" "$ADMIN_PID_FILE" "$ADMIN_PATTERN" >/dev/null 2>&1 || true
sleep 1

( cd apps/api && setsid node dist/main.js > "$LOG_DIR/api.log" 2>&1 < /dev/null & ) \
  >/dev/null 2>&1 </dev/null
wait_for api 45 curl -sf "http://localhost:$API_PORT/api/plans" \
  || { tail -20 "$LOG_DIR/api.log"; die "the API did not start — see .logs/api.log"; }
resolve_pid "$API_PORT" "$API_PID_FILE" "$API_PATTERN" > "$API_PID_FILE" || true
ok "api       http://localhost:$API_PORT/api"

( cd apps/admin && setsid ./node_modules/.bin/next start -p "$ADMIN_PORT" \
    > "$LOG_DIR/admin.log" 2>&1 < /dev/null & ) \
  >/dev/null 2>&1 </dev/null
wait_for admin 45 curl -sf "http://localhost:$ADMIN_PORT" \
  || { tail -20 "$LOG_DIR/admin.log"; die "the admin panel did not start — see .logs/admin.log"; }
resolve_pid "$ADMIN_PORT" "$ADMIN_PID_FILE" "$ADMIN_PATTERN" > "$ADMIN_PID_FILE" || true
ok "admin     http://localhost:$ADMIN_PORT"

# ---------------------------------------------------------------------- summary
ADMIN_EMAIL=$(grep -E '^SEED_ADMIN_EMAIL=' apps/api/.env | cut -d= -f2-)
ADMIN_PASS=$(grep -E '^SEED_ADMIN_PASSWORD=' apps/api/.env | cut -d= -f2-)

cat <<EOF

${bold}Running${reset}

  Admin panel   ${bold}http://localhost:$ADMIN_PORT${reset}
  API           http://localhost:$API_PORT/api
  API docs      http://localhost:$API_PORT/api/docs

  Sign in as    ${ADMIN_EMAIL:-admin@example.com} / ${ADMIN_PASS:-ChangeMe123!}

${bold}Mobile app${reset}

  pnpm --filter @tsp/mobile start        ${dim}# Expo dev server, scan with Expo Go${reset}
  pnpm --filter @tsp/mobile run android  ${dim}# build to a connected device${reset}

${dim}./start.sh --status    what is running
./start.sh --logs      tail the API log
./start.sh --stop      stop the API and admin panel${reset}

EOF
