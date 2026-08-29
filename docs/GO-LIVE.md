# Go live

Ordered by dependency, not by vendor. Work down it, and run `./preflight.sh`
after each step — it makes a real authenticated call to each provider, so it
tells you whether a credential *works*, not merely whether you pasted something.

```bash
./preflight.sh              # what is ready, what is missing, what it costs you
./preflight.sh --quiet      # only the problems
./preflight.sh --self-test  # prove the checker itself classifies correctly
```

`✗ blocker` means fix it before taking money. `! degraded` means you can launch,
but a specific feature is off. The exit code is non-zero while any blocker
stands, so it can gate a deploy.

> **Open item before launch.** The signal composer has no chart-screenshot
> upload. The whole pipeline behind it exists — upload endpoint, watermarking,
> storage, the mobile renderer, Telegram photo posting — but
> `apps/admin/src/app/signals/new/page.tsx` sends `imageIds: []`, so nothing can
> be attached. "Chart screenshot with every setup" is a listed feature of the
> $75 plan, so either build that control or remove the claim from the plan copy
> and the store listing.

---

## 1. Secrets and the database

Nothing else matters until these are right.

| Variable | Where it comes from |
|---|---|
| `DATABASE_URL` | Your managed Postgres. Keep `?schema=public`. |
| `JWT_SECRET` | `./preflight.sh --fix-secrets` |
| `SEED_ADMIN_PASSWORD` | Choose one, then re-seed |
| `API_PUBLIC_URL` | The public HTTPS origin of your API |

The default `JWT_SECRET` is a known string in a public repo — anyone who reads
it can mint an admin token for any deployment still using it. `--fix-secrets`
replaces it with 48 bytes of entropy. **Changing it signs everyone out**, which
is exactly what you want if it was ever the default.

Then change the admin password and re-seed:

```bash
# edit SEED_ADMIN_PASSWORD in apps/api/.env first
pnpm --filter @tsp/api db:seed
```

**Verify:** `./preflight.sh` shows `DATABASE_URL reachable, 5 plans seeded` and
a green `JWT_SECRET`.

---

## 2. Payments

You are on external rails, so this is your entire revenue path.

### Stripe — cards

1. Create the account and complete onboarding (payouts need a verified business).
2. **Developers → API keys** → the secret key → `STRIPE_SECRET_KEY`.
   `sk_test_` moves no real money; preflight tells you which mode you are in.
3. **Developers → Webhooks → Add endpoint**:
   - URL `https://YOUR-API/api/webhooks/stripe`
   - Event: `checkout.session.completed`
   - Copy the signing secret → `STRIPE_WEBHOOK_SECRET`

The webhook is not optional. Checkout redirecting the customer back to the app
grants nothing — a redirect can be forged and a customer can close the tab. The
signed webhook is the only thing that credits a payment. **Without
`STRIPE_WEBHOOK_SECRET` a customer can pay and stay locked out.**

Locally:

```bash
stripe listen --forward-to localhost:3000/api/webhooks/stripe
```

**Verify end to end** — this is the one test worth doing by hand:

1. Buy the Signals plan in the app with test card `4242 4242 4242 4242`.
2. `Payment.status` becomes `PAID` and a `Subscription` goes `ACTIVE`.
3. A previously locked signal now returns its levels.
4. Ads stop rendering for that account.

### Crypto — NOWPayments

`NOWPAYMENTS_API_KEY` and `NOWPAYMENTS_IPN_SECRET`, IPN URL
`https://YOUR-API/api/webhooks/crypto`.

Leave the key empty and crypto still works as a manual flow: the buyer sends
funds and submits a transaction hash, you approve it in **Payment queue**. That
is a reasonable way to launch — it costs you nothing and needs no merchant
account.

### Bank transfer

`BANK_TRANSFER_INSTRUCTIONS` is shown in-app. Worth setting: on a $5,000 plan a
transfer avoids all processing fees, and buyers at that price often prefer it.
Approve in **Payment queue**.

---

## 3. Video — Cloudflare Stream

The recorded library *is* the $100 plan. Without this, every lesson fails.

1. **Cloudflare → Stream**, note the **Account ID** → `CF_ACCOUNT_ID`.
2. API token with `Stream:Read` and `Stream:Edit` → `CF_STREAM_API_TOKEN`.
3. **Stream → Settings → Signing keys → Create**. You get a key ID and a PEM.
   - `CF_STREAM_SIGNING_KEY_ID` = the key id
   - `CF_STREAM_SIGNING_KEY_PEM` = the **whole PEM, base64-encoded**:
     ```bash
     base64 -w0 < signing-key.pem
     ```

Signed URLs are what make the library sellable. Without the signing key the
backend cannot mint playback tokens; serving raw Stream URLs instead would let
one subscriber share the entire library with a link.

Upload a video in the Cloudflare dashboard, copy its UID, and paste it into the
lesson in **Courses**. (There is no direct upload from the admin panel yet.)

**Verify:** open a lesson as a subscriber — it plays; the response contains a
signed URL and no `videoUid`; replaying that URL after `CF_STREAM_TOKEN_TTL_SEC`
fails.

---

## 4. Telegram

1. `@BotFather` → `/newbot` → token → `TELEGRAM_BOT_TOKEN`.
2. Add the bot to your channel **as an administrator**, then put the channel id
   (`-100…`) in `TELEGRAM_PUBLIC_CHANNEL_ID`.

Preflight prints the bot's `@username` when the token is valid — if the name
surprises you, you pasted the wrong token.

**Scaling caveat.** `TELEGRAM_USE_POLLING=true` requires exactly **one** API
instance. Two instances both poll, and every subscriber receives every signal
twice. Before scaling out, switch to webhooks.

**Verify:** publish a signal. The channel gets a locked teaser; a linked
subscriber gets the full levels by DM. Then tap *Move to BE* — the **existing**
message is edited, not replaced.

---

## 5. Live coaching — Daily.co

`DAILY_API_KEY` and `DAILY_DOMAIN`. Without it, Pro and Ultra subscribers can
book a session and then cannot join it — on the $1,500 and $5,000 plans.

Keep coaching **one-to-one**. Apple guideline 3.1.3(d) permits outside payment
only for real-time services *between two individuals*; a group session would
force those plans onto in-app purchase and cost you 15–30%. See
[`COMPLIANCE.md`](./COMPLIANCE.md).

---

## 6. Push and ads

**Push:** `EXPO_ACCESS_TOKEN` from expo.dev → Access tokens. Push works without
it but Expo throttles at volume. For a production build you also need FCM (Play)
and an APNs key (Apple) uploaded to EAS.

**Ads:** create the AdMob app and ad units, then set the unit ids per placement
in **Ads**. Preflight warns if a placement is enabled with a blank unit id —
it renders nothing.

Two things to leave alone: Pro and Ultra receive no unit ids at all (they paid
not to see ads, and it is enforced server-side), and there are no ads in the
lesson player — interrupting a $100/month course for a few cents is a bad trade.

Add `app-ads.txt` to your marketing domain, or AdMob restricts your fill.

---

## 7. Store builds

Identity comes from `apps/mobile/eas.json` via `app.config.js`. Set the
production profile before building — the bundle id and package name are
**permanent once published**:

```json
"production": {
  "env": {
    "EXPO_PUBLIC_API_URL": "https://api.yourdomain.com/api",
    "APP_BUNDLE_ID": "com.yourdomain.signals"
  }
}
```

```bash
cd apps/mobile
eas init                              # writes your EAS project id
eas build --profile preview --platform android   # installable APK, test on a real device
eas build --profile production --platform android
eas submit --platform android
```

**Android first.** Play is materially more permissive about external payment for
this category, so you get revenue and a track record while iOS review runs.
For `eas submit` fill the `REPLACE_WITH_*` Apple fields and add your Play
service-account JSON.

Before submitting, read [`COMPLIANCE.md`](./COMPLIANCE.md) — the **Google Play
Financial Features Declaration** blocks every release on your account until it
is filed, and it is not specific to this app.

---

## Final check

```bash
./preflight.sh
```

Green on every blocker, then:

- [ ] Test-card purchase unlocks a signal and stops the ads
- [ ] A lesson plays, and the stale URL stops working
- [ ] A signal reaches Telegram, and an update **edits** that message
- [ ] Play Financial Features Declaration filed
- [ ] Privacy policy and terms hosted and linked in both listings
- [ ] Reviewer demo account seeded on the **Ultra** tier — a reviewer who cannot
      see paid content rejects for incomplete functionality
- [ ] Chart-screenshot upload built, or the claim removed from the $75 plan copy
- [ ] Repository set to private if the source should not be public
