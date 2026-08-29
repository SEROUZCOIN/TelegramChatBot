#!/usr/bin/env bash
#
# Launch readiness check.
#
#   ./preflight.sh                what is configured, what is broken, what it costs
#   ./preflight.sh --fix-secrets  generate a real JWT_SECRET in place
#   ./preflight.sh --quiet        only problems
#
# Every credential is reported in one of three states:
#
#   ready    present, and where the provider allows a read-only call, it worked
#   missing  absent — the feature it powers is named
#   broken   present but the provider rejected it
#
# The distinction matters. A check that only tests for a non-empty string is
# worse than no check at all, because it reports green on a typo'd key and you
# find out when a customer's payment fails. So wherever a provider offers a
# cheap authenticated read, this makes it. Nothing here writes or mutates.
#
# Exit code is non-zero when a launch blocker is unmet, so it can gate a deploy.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/apps/api/.env"
APP_JSON="$ROOT/apps/mobile/app.json"
EAS_JSON="$ROOT/apps/mobile/eas.json"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'
red=$'\033[31m'; blue=$'\033[34m'; reset=$'\033[0m'

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

BLOCKERS=0   # unmet items that must be fixed before launch
WARNINGS=0   # unmet items that degrade the product but do not block

step() { printf '\n%s==>%s %s\n' "$blue$bold" "$reset" "$1"; }

ready() {
  [ "$QUIET" = 1 ] && return 0
  printf '    %s✓%s %-26s %s\n' "$green" "$reset" "$1" "${2:-}"
}

# An unmet item that stops you launching.
blocker() {
  printf '    %s✗%s %-26s %s\n' "$red" "$reset" "$1" "$2"
  BLOCKERS=$((BLOCKERS + 1))
}

# An unmet item that costs you a feature but does not stop a launch.
degraded() {
  printf '    %s!%s %-26s %s\n' "$yellow" "$reset" "$1" "$2"
  WARNINGS=$((WARNINGS + 1))
}

note() { [ "$QUIET" = 1 ] || printf '      %s%s%s\n' "$dim" "$1" "$reset"; }

# Read one variable out of the API's .env without sourcing the file — sourcing
# would execute whatever happens to be in there.
env_get() {
  [ -f "$ENV_FILE" ] || return 1
  local line
  line="$(grep -m1 -E "^$1=" "$ENV_FILE" 2>/dev/null)" || return 1
  printf '%s' "${line#*=}" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

have() { [ -n "${1:-}" ]; }

# Prisma's connection string carries options libpq does not accept — `?schema=`
# above all, which makes psql fail with "invalid URI query parameter" on a
# perfectly good database. Strip the query string before probing.
pg_url() { printf '%s' "${1%%\?*}"; }

# A short authenticated GET, printing just the HTTP status so callers can tell
# an auth failure (401/403) from an outage or a blocked egress (000).
#
# No `|| echo 000` here: curl's own -w already prints 000 when the request
# never completed, so a fallback would concatenate into "000000" and fall
# through every case arm.
http_status() {
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 "$@" 2>/dev/null)"
  case "$code" in
    ''|*[!0-9]*) printf '000' ;;
    *) printf '%s' "$code" ;;
  esac
}

# Turn an HTTP status from a credential probe into one of the three states.
#
# This is the judgement the whole script rests on, so it is a function rather
# than five copies of a case statement: a rejected key must never read as ready,
# and the checker's own network trouble must never read as a rejected key.
#
#   $1 label  $2 status  $3 detail shown when it worked
#   $4 what it means when the provider rejected it
classify_http() {
  local label="$1" code="$2" ok_detail="$3" reject_detail="$4"
  case "$code" in
    2*)      ready   "$label" "$ok_detail" ;;
    401|403) blocker "$label" "$reject_detail (HTTP $code)"
             note "present but rejected — reissue or correct it" ;;
    000)     degraded "$label" "set, but the provider was unreachable from here"
             note "network or egress problem, not necessarily a bad credential" ;;
    *)       degraded "$label" "set, but the provider answered HTTP $code" ;;
  esac
}

# Exercise the classification against every status that matters, without
# needing any provider to be reachable. Run: ./preflight.sh --self-test
if [ "${1:-}" = "--self-test" ]; then
  FAILED=0
  assert_state() {
    local expect="$1" code="$2" out
    out="$(BLOCKERS=0 WARNINGS=0; classify_http "probe" "$code" "ok" "rejected" 2>&1)"
    case "$out" in
      *"✓"*) got=ready ;;
      *"✗"*) got=blocker ;;
      *"!"*) got=degraded ;;
      *)     got=none ;;
    esac
    if [ "$got" = "$expect" ]; then
      printf '    %s✓%s HTTP %-4s -> %s\n' "$green" "$reset" "$code" "$got"
    else
      printf '    %s✗%s HTTP %-4s -> %s (expected %s)\n' "$red" "$reset" "$code" "$got" "$expect"
      FAILED=$((FAILED + 1))
    fi
  }

  step "Classification self-test"
  assert_state ready    200
  assert_state ready    204
  assert_state blocker  401
  assert_state blocker  403
  assert_state degraded 000
  assert_state degraded 500
  assert_state degraded 429

  if [ "$FAILED" -eq 0 ]; then
    printf '\n%s✓ classification is correct for every status%s\n\n' "$green$bold" "$reset"
    exit 0
  fi
  printf '\n%s✗ %d classification failures%s\n\n' "$red$bold" "$FAILED" "$reset"
  exit 1
fi

json_field() {
  python3 -c "
import json,sys
try:
    d = json.load(open(sys.argv[1]))
    for k in sys.argv[2].split('.'):
        d = d[k]
    print(d)
except Exception:
    pass
" "$1" "$2" 2>/dev/null
}

printf '%sLaunch readiness%s  %s%s%s\n' "$bold" "$reset" "$dim" "$(date '+%Y-%m-%d %H:%M')" "$reset"

if [ ! -f "$ENV_FILE" ]; then
  printf '\n%s✗%s apps/api/.env does not exist. Run ./start.sh once to create it.\n' "$red" "$reset"
  exit 1
fi

# ------------------------------------------------------------- fix-secrets
if [ "${1:-}" = "--fix-secrets" ]; then
  step "Generating a new JWT_SECRET"
  NEW_SECRET="$(openssl rand -base64 48 2>/dev/null | tr -d '\n')"
  if [ -z "$NEW_SECRET" ]; then
    printf '    %s✗%s openssl is unavailable — cannot generate a secret\n' "$red" "$reset"
    exit 1
  fi
  # Delimiter is | because base64 contains / and +.
  sed -i.bak "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_SECRET|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  printf '    %s✓%s JWT_SECRET replaced with 48 bytes of entropy\n' "$green" "$reset"
  printf '      %sEvery existing session is now invalid — users sign in again.%s\n' "$dim" "$reset"
  exit 0
fi

# ============================================================ BLOCKS LAUNCH
step "Blocks launch"

DATABASE_URL="$(env_get DATABASE_URL)"
if ! have "$DATABASE_URL"; then
  blocker "DATABASE_URL" "not set — the API cannot start"
elif command -v psql >/dev/null 2>&1; then
  PG_URL="$(pg_url "$DATABASE_URL")"
  if psql "$PG_URL" -tAc 'SELECT 1' >/dev/null 2>&1; then
    PLANS="$(psql "$PG_URL" -tAc 'SELECT count(*) FROM plans' 2>/dev/null || echo '?')"
    ready "DATABASE_URL" "reachable, $PLANS plans seeded"
  else
    blocker "DATABASE_URL" "set but the database refused the connection"
    note "check the host, port and password in apps/api/.env"
  fi
else
  degraded "DATABASE_URL" "set, but psql is missing so it could not be tested"
fi

JWT_SECRET="$(env_get JWT_SECRET)"
if ! have "$JWT_SECRET"; then
  blocker "JWT_SECRET" "not set — the API will not sign tokens"
elif [ "$JWT_SECRET" = "change-me-in-production" ] || [ ${#JWT_SECRET} -lt 32 ]; then
  blocker "JWT_SECRET" "still the default, or too short"
  note "anyone with the repo can mint admin tokens — run: ./preflight.sh --fix-secrets"
else
  ready "JWT_SECRET" "${#JWT_SECRET} characters"
fi

SEED_PASS="$(env_get SEED_ADMIN_PASSWORD)"
if [ "$SEED_PASS" = "ChangeMe123!" ]; then
  blocker "SEED_ADMIN_PASSWORD" "still the documented default"
  note "the admin account owns every payment and plan — change it, then re-seed"
elif have "$SEED_PASS"; then
  ready "SEED_ADMIN_PASSWORD" "changed from the default"
else
  degraded "SEED_ADMIN_PASSWORD" "not set — seeding will use the default"
fi

API_URL="$(env_get API_PUBLIC_URL)"
case "$API_URL" in
  ""|*localhost*|*127.0.0.1*)
    degraded "API_PUBLIC_URL" "still local — webhooks and the app cannot reach it"
    note "set this to the public HTTPS URL before registering any webhook" ;;
  https://*) ready "API_PUBLIC_URL" "$API_URL" ;;
  *) degraded "API_PUBLIC_URL" "not HTTPS — stores and payment providers require TLS" ;;
esac

# =========================================================== BLOCKS REVENUE
step "Blocks revenue"

STRIPE_KEY="$(env_get STRIPE_SECRET_KEY)"
if ! have "$STRIPE_KEY"; then
  degraded "STRIPE_SECRET_KEY" "missing — card payment is not offered at all"
  note "the plans endpoint simply omits STRIPE; crypto and bank still work"
else
  CODE="$(http_status -H "Authorization: Bearer $STRIPE_KEY" https://api.stripe.com/v1/balance)"
  case "$STRIPE_KEY" in
    sk_live_*) MODE="valid, LIVE mode" ;;
    *)         MODE="valid, TEST mode — no real money moves" ;;
  esac
  classify_http "STRIPE_SECRET_KEY" "$CODE" "$MODE" "rejected by Stripe"

  STRIPE_WH="$(env_get STRIPE_WEBHOOK_SECRET)"
  if ! have "$STRIPE_WH"; then
    blocker "STRIPE_WEBHOOK_SECRET" "missing — payments will never be credited"
    note "checkout succeeds, the webhook is rejected, the customer pays and stays locked out"
  elif [[ "$STRIPE_WH" != whsec_* ]]; then
    degraded "STRIPE_WEBHOOK_SECRET" "does not look like a Stripe signing secret"
  else
    ready "STRIPE_WEBHOOK_SECRET" "set"
    note "register: ${API_URL:-<API_PUBLIC_URL>}/api/webhooks/stripe"
  fi
fi

NOWPAY_KEY="$(env_get NOWPAYMENTS_API_KEY)"
if ! have "$NOWPAY_KEY"; then
  degraded "NOWPAYMENTS_API_KEY" "missing — crypto falls back to manual review"
  note "buyers send funds and submit a hash; you approve it in the payment queue"
else
  CODE="$(http_status -H "x-api-key: $NOWPAY_KEY" https://api.nowpayments.io/v1/status)"
  classify_http "NOWPAYMENTS_API_KEY" "$CODE" "valid" "rejected by NOWPayments"
  have "$(env_get NOWPAYMENTS_IPN_SECRET)" \
    && ready "NOWPAYMENTS_IPN_SECRET" "set" \
    || blocker "NOWPAYMENTS_IPN_SECRET" "missing — crypto payments cannot be verified"
fi

if ! have "$(env_get BANK_TRANSFER_INSTRUCTIONS)"; then
  degraded "BANK_TRANSFER_INSTRUCTIONS" "empty — bank transfer is hidden"
  note "worth setting: a \$5,000 buyer often prefers a transfer, and it costs no fee"
else
  ready "BANK_TRANSFER_INSTRUCTIONS" "set"
fi

# =================================================== BLOCKS THE PAID PRODUCT
step "Blocks the paid product"

CF_ACCOUNT="$(env_get CF_ACCOUNT_ID)"
CF_TOKEN="$(env_get CF_STREAM_API_TOKEN)"
if ! have "$CF_TOKEN" || ! have "$CF_ACCOUNT"; then
  blocker "CF_STREAM" "missing — the \$100 video library cannot play"
  note "every lesson returns 'video playback is not configured'"
else
  CODE="$(http_status -H "Authorization: Bearer $CF_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/stream?per_page=1")"
  if [ "$CODE" = "404" ]; then
    # Distinct from an auth failure: the token is fine, the account is wrong.
    blocker "CF_ACCOUNT_ID" "no such account, or Stream is not enabled on it"
  else
    classify_http "CF_STREAM_API_TOKEN" "$CODE" "valid for account $CF_ACCOUNT" \
      "rejected by Cloudflare — needs Stream:Read"
  fi
fi

CF_KEY_ID="$(env_get CF_STREAM_SIGNING_KEY_ID)"
CF_PEM="$(env_get CF_STREAM_SIGNING_KEY_PEM)"
if ! have "$CF_KEY_ID" || ! have "$CF_PEM"; then
  blocker "CF_STREAM signing key" "missing — playback tokens cannot be signed"
  note "without it the library is either unplayable or, if you serve raw URLs, unprotected"
else
  DECODED="$(printf '%s' "$CF_PEM" | base64 -d 2>/dev/null | head -1)"
  case "$DECODED" in
    *"PRIVATE KEY"*) ready "CF_STREAM signing key" "base64 PEM decodes correctly" ;;
    *) blocker "CF_STREAM_SIGNING_KEY_PEM" "does not decode to a PEM private key"
       note "it must be the base64 of the whole PEM, newlines included" ;;
  esac
fi

# ========================================================== BLOCKS DELIVERY
step "Blocks delivery"

TG_TOKEN="$(env_get TELEGRAM_BOT_TOKEN)"
if ! have "$TG_TOKEN"; then
  degraded "TELEGRAM_BOT_TOKEN" "missing — no signal reaches Telegram"
  note "the in-app feed still works; you lose the funnel and the subscriber bot"
else
  BOT_JSON="$(curl -sS --max-time 12 "https://api.telegram.org/bot$TG_TOKEN/getMe" 2>/dev/null)"
  if printf '%s' "$BOT_JSON" | grep -q '"ok":true'; then
    BOT_NAME="$(printf '%s' "$BOT_JSON" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
    ready "TELEGRAM_BOT_TOKEN" "valid — @${BOT_NAME:-unknown}"
  elif printf '%s' "$BOT_JSON" | grep -q '"ok":false'; then
    blocker "TELEGRAM_BOT_TOKEN" "rejected by Telegram"
    note "revoked or mistyped — reissue it with @BotFather"
  else
    degraded "TELEGRAM_BOT_TOKEN" "set, but Telegram was unreachable from here"
  fi

  have "$(env_get TELEGRAM_PUBLIC_CHANNEL_ID)" \
    && ready "TELEGRAM_PUBLIC_CHANNEL_ID" "set" \
    || degraded "TELEGRAM_PUBLIC_CHANNEL_ID" "empty — no public teaser is posted"

  if [ "$(env_get TELEGRAM_USE_POLLING)" = "true" ]; then
    note "polling is on: run exactly ONE API instance, or every subscriber gets duplicates"
  fi
fi

EXPO_TOKEN="$(env_get EXPO_ACCESS_TOKEN)"
if ! have "$EXPO_TOKEN"; then
  degraded "EXPO_ACCESS_TOKEN" "missing — push notifications are rate-limited"
  note "push still works unauthenticated, but Expo throttles it at volume"
else
  CODE="$(http_status -H "Authorization: Bearer $EXPO_TOKEN" https://exp.host/--/api/v2/push/getReceipts \
          -X POST -H 'content-type: application/json' -d '{"ids":[]}')"
  classify_http "EXPO_ACCESS_TOKEN" "$CODE" "valid" "rejected by Expo"
fi

# ========================================================== BLOCKS COACHING
step "Blocks coaching"

DAILY_KEY="$(env_get DAILY_API_KEY)"
if ! have "$DAILY_KEY"; then
  blocker "DAILY_API_KEY" "missing — Pro and Ultra cannot hold a session"
  note "those are the \$1,500 and \$5,000 plans; booking works, joining fails"
else
  CODE="$(http_status -H "Authorization: Bearer $DAILY_KEY" https://api.daily.co/v1/)"
  classify_http "DAILY_API_KEY" "$CODE" "valid" "rejected by Daily"
fi

# ======================================================== BLOCKS AD REVENUE
step "Blocks ad revenue"

PG_URL="$(pg_url "${DATABASE_URL:-}")"
if have "$PG_URL" && command -v psql >/dev/null 2>&1 \
   && psql "$PG_URL" -tAc 'SELECT 1' >/dev/null 2>&1; then
  ENABLED="$(psql "$PG_URL" -tAc \
    'SELECT count(*) FROM ad_placements WHERE "isEnabled" = true' 2>/dev/null || echo 0)"
  BLANK="$(psql "$PG_URL" -tAc \
    'SELECT count(*) FROM ad_placements WHERE "isEnabled" = true
       AND ("unitIdIos" = '"''"' OR "unitIdAndroid" = '"''"')' 2>/dev/null || echo 0)"

  if [ "${ENABLED:-0}" = "0" ]; then
    degraded "AdMob placements" "none enabled — no ad revenue"
    note "enable them in the admin panel once you have real ad unit ids"
  elif [ "${BLANK:-0}" != "0" ]; then
    degraded "AdMob placements" "$BLANK of $ENABLED enabled with a blank unit id"
    note "those slots render nothing at all"
  else
    ready "AdMob placements" "$ENABLED enabled, all with unit ids"
  fi
else
  degraded "AdMob placements" "could not be checked — no database connection"
fi

# ========================================================= STORE READINESS
step "Store readiness"

# Identity now comes from the environment through app.config.js, and for a real
# build that environment is the eas.json production profile — so that profile,
# not a static app.json, is what has to be right.
if [ -f "$EAS_JSON" ]; then
  PROD_BUNDLE="$(json_field "$EAS_JSON" build.production.env.APP_BUNDLE_ID)"
  PROD_API="$(json_field "$EAS_JSON" build.production.env.EXPO_PUBLIC_API_URL)"

  case "$PROD_BUNDLE" in
    com.example.*|"")
      blocker "production bundle id" "still ${PROD_BUNDLE:-unset}"
      note "Apple and Google both reject com.example.*, and it is permanent once published"
      note "set build.production.env.APP_BUNDLE_ID in apps/mobile/eas.json" ;;
    *) ready "production bundle id" "$PROD_BUNDLE" ;;
  esac

  case "$PROD_API" in
    *example.com*|*localhost*|"")
      blocker "production API URL" "still ${PROD_API:-unset}"
      note "a shipped build would point at a domain you do not run" ;;
    https://*) ready "production API URL" "$PROD_API" ;;
    *) blocker "production API URL" "not HTTPS — the app will refuse the connection" ;;
  esac

  if grep -q "REPLACE_WITH" "$EAS_JSON"; then
    degraded "eas.json submit fields" "Apple placeholders unfilled"
    note "needed only for 'eas submit'; 'eas build' works without them"
  else
    ready "eas.json submit fields" "filled"
  fi
fi

# EAS_PROJECT_ID is not stored in the repo — `eas init` writes it to the EAS
# account and it arrives through the environment — so check the environment.
PROJ_ID="${EAS_PROJECT_ID:-}"
if [ -z "$PROJ_ID" ] && [ -f "$APP_JSON" ]; then
  PROJ_ID="$(json_field "$APP_JSON" expo.extra.eas.projectId)"
fi
case "$PROJ_ID" in
  00000000-0000-0000-0000-000000000000|"")
    blocker "EAS projectId" "not set — every build fails immediately"
    note "run: cd apps/mobile && eas init" ;;
  *) ready "EAS projectId" "$PROJ_ID" ;;
esac

# ------------------------------------------------------------------ summary
printf '\n%s%s%s\n' "$bold" "────────────────────────────────────────────────────────" "$reset"

if [ "$BLOCKERS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  printf '%s✓ Ready to launch.%s Everything checked is configured and accepted.\n\n' "$green$bold" "$reset"
  exit 0
fi

if [ "$BLOCKERS" -gt 0 ]; then
  printf '%s✗ %d blocker%s%s' "$red$bold" "$BLOCKERS" "$([ "$BLOCKERS" -eq 1 ] || echo s)" "$reset"
  [ "$WARNINGS" -gt 0 ] && printf '   %s! %d degraded%s' "$yellow" "$WARNINGS" "$reset"
  printf '\n\n%sFix the blockers before taking a payment. See docs/GO-LIVE.md.%s\n\n' "$dim" "$reset"
  exit 1
fi

printf '%s! %d degraded%s — nothing blocks a launch, but each one costs a feature.\n' \
  "$yellow$bold" "$WARNINGS" "$reset"
printf '%sSee docs/GO-LIVE.md.%s\n\n' "$dim" "$reset"
exit 0
