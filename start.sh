#!/usr/bin/env bash
#
# Convenience wrapper. The launcher itself is run.js.
#
#   ./start.sh              start everything
#   ./start.sh --stop       stop the API and admin panel
#   ./start.sh --status     show what is running
#   ./start.sh --logs       follow the API log
#   ./start.sh --reset-db   drop and rebuild the database, then start
#
# This used to be the launcher, written in bash. It could only ever run on
# Linux — `service postgresql`, `su postgres`, `pg_isready` and `lsof` have no
# Windows equivalent — so the logic moved to run.js, which is plain Node and
# runs anywhere Node does. Keeping one implementation means the two cannot
# drift apart; this file survives only so existing habits keep working.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  printf '\033[31m✗\033[0m Node is not installed. Get the LTS build from https://nodejs.org\n'
  exit 1
fi

exec node "$ROOT/run.js" "$@"
