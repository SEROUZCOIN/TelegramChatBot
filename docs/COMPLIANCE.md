# Store compliance

Read this before submitting to either store. Two items here are hard blockers,
and the payment routing has a specific rationale the code is built around.

---

## Hard blockers

### 1. Google Play Financial Features Declaration

Global enforcement began **28 January 2026**. Until the declaration is filed in
Play Console you cannot publish *any* update — this is not specific to financial
apps, it gates every release on the account.

Play Console → App content → Financial features. Declare the app as an
information/education service. It does **not** offer:

- trading or brokerage execution
- binary options (banned outright by Play — do not add them)
- lending, deposits, or custody of funds

### 2. In-app account deletion

Apple guideline 5.1.1(v) requires it for any app with account creation, and its
absence is a routine rejection. Implemented at Profile → Delete my account
(`DELETE /api/me`).

---

## The payment routing, and why it is what it is

Everything runs on **external** rails — Stripe, crypto, bank transfer — keeping
roughly 97% of revenue instead of a 15–30% store commission. That is a
deliberate choice, and the exposure is not uniform across the plans.

| Plan | What it sells | Rule | Position |
|---|---|---|---|
| Signals $75/mo | Trade analysis | 3.1.1 | External. Some risk. |
| Normal $100/mo | Recorded video | **3.1.1** | **External. This is the exposure.** |
| Pro $1,500 | Live 1-on-1 coaching | **3.1.3(d)** | External. Explicitly permitted. |
| Ultra $5,000 | Live 1-on-1 coaching | **3.1.3(d)** | External. Explicitly permitted. |

**Guideline 3.1.3(d)** permits outside payment for *"real-time person-to-person
services between two individuals (for example tutoring students, medical
consultations, real estate tours, or fitness training)"*. One-to-one coaching is
squarely within this. It also says *"one-to-few and one-to-many real-time
services must use in-app purchase"* — which is why coaching in this codebase is
1:1 only and has no group-session feature. Adding one would forfeit the
exemption on the two highest-value plans.

**Guideline 3.1.1** requires in-app purchase to unlock digital content. The
Normal plan sells recorded video, so it is the likely rejection trigger.

### The prepared answer

Every plan carries a `paymentMode` column (`EXTERNAL | IAP | BOTH`). All four
payment providers — including a RevenueCat-backed IAP provider — are implemented
and registered; the IAP one is simply never selected because no plan allows it.

If App Review objects to the Normal plan:

1. Admin panel → Plans & pricing → Normal → Payment rail → **In-app purchase**.
2. Set `iapProductIdIos` / `iapProductIdAndroid` to your store product ids.
3. Set `REVENUECAT_API_KEY` and `REVENUECAT_WEBHOOK_SECRET`.

No code change. No new build in the review queue. One database row.

### Submission order

**Ship Android first.** Play is materially more permissive about external
payment for this category, so you get revenue flowing and a production track
record while iOS review runs. Submit iOS second.

### Price ceiling

Apple's price points run to $10,000, but everything above the standard band
requires a separate request and approval. The $5,000 Ultra tier only matters
here if you ever move it to IAP — on external rails there is no ceiling.

---

## Staying on the education side of 3.2.1(viii)

> *"Apps used for financial trading, investing, or money management should be
> submitted by the financial institution performing such services and must have
> necessary licensing and permissions in the locations where you make them
> available."*

Guideline **3.2.2(viii)** adds that apps facilitating CFD or forex trading must
be licensed everywhere they are available.

This app is approvable because it does none of that. It **must not** start:

- executing trades or placing orders
- connecting to, authenticating against, or reading a brokerage account
- holding, transmitting, or custodying user funds
- offering copy-trading or auto-execution
- giving personalised advice — signals go to a whole tier, never to an individual

Adding any one of these converts the app into a regulated financial product and
you would need actual licensing. The MT5 bridge is safe precisely because it is
one-way: the Expert Advisor *reports* trades you placed yourself and never
receives an instruction.

Also required, and already implemented:

- Risk disclaimer accepted before the app opens, version recorded per user
- A disclaimer on every signal surface
- No "guaranteed profit" language anywhere — app, listing, bot, or marketing
- Performance figures presented as history, never as a forecast

---

## Ads

`react-native-google-mobile-ads`, configured server-side per placement.

- **App Tracking Transparency** (guideline 5.1.2(i)) is requested before any
  personalised ad, and only from users who will actually see ads.
- Pro and Ultra receive **no ad unit ids at all** — suppression is server-side,
  so it holds regardless of the client build.
- Under AdSense/AdMob publisher policy, CFD and rolling-spot-forex content is
  *restricted*; expect lower fill and inventory than a general-audience app.
- Keep ads out of the paid course player. Interrupting a $100/month lesson to
  serve a banner trades real revenue for a few cents.

---

## App Store Connect answers

| Question | Answer |
|---|---|
| Age rating | 17+ (simulated gambling: no; unrestricted web: no; frequent mature themes: no) |
| Encryption | HTTPS only — `usesNonExemptEncryption: false` is set in `app.json` |
| Account deletion | Yes, in-app under Profile |
| Data collection | Email, name, usage, device id for ads — declare all in App Privacy |
| Third-party ads | Yes, AdMob |
| Demo account | Provide reviewers a **seeded Ultra account**. A reviewer who cannot see paid content will reject for incomplete functionality. |

## Play Console answers

| Question | Answer |
|---|---|
| Financial features | Declare — mandatory, blocks all releases |
| Ads | Yes |
| Data safety | Email, name, device id, usage; encrypted in transit; deletable in-app |
| Target audience | 18+ |
| Content rating | Complete the IARC questionnaire; finance/education, no gambling |

---

## Before you ship

- [ ] Google Play Financial Features Declaration filed
- [ ] Privacy policy and terms hosted, and linked in both listings
- [ ] `JWT_SECRET` set to a real generated value, never the default
- [ ] Seeded admin password changed from `ChangeMe123!`
- [ ] Reviewer demo account created on the Ultra tier
- [ ] Bundle identifiers changed from `com.example.*`
- [ ] Store listing copy contains no profit claims
- [ ] Cloudflare Stream signing keys configured — the video library is unprotected without them
- [ ] Stripe/crypto webhooks pointed at the production API and verified
