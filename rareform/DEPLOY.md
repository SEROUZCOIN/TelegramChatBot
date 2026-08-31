# Deploying RAREFORM on Cloudflare, free

The site is a static build — no server, no database, no environment variables.
Cloudflare Pages hosts it free, with HTTPS and a global CDN included.

```bash
cd rareform
npm install
npm run build      # -> dist/   (this is the whole site)
npm run bundle     # -> dist/rareform.html, one self-contained file
```

Everything below is already committed: `wrangler.toml`, `public/_headers`,
`public/_redirects`, and a GitHub Actions workflow.

---

## 1. Get it live

Two routes. Pick one — the first needs no secrets.

### Route A — connect the repo in the Cloudflare dashboard (about two minutes)

1. Sign in at **dash.cloudflare.com** → **Workers & Pages** → **Create** →
   **Pages** → **Connect to Git**.
2. Authorise GitHub and pick `SEROUZCOIN/TelegramChatBot`.
3. Set the build settings:

   | Field | Value |
   |---|---|
   | Production branch | `claude/clothing-marketplace-3d-render-4vzolb` |
   | Framework preset | Vite |
   | Build command | `npm run build` |
   | Build output directory | `dist` |
   | Root directory | `rareform` |

4. **Save and Deploy.** You get `https://rareform.pages.dev` — live, on HTTPS,
   and it rebuilds on every push.

### Route B — deploy from GitHub Actions

`.github/workflows/deploy-rareform.yml` already builds the site on every push
that touches `rareform/`. It publishes to Cloudflare Pages as soon as two
repository secrets exist, and passes without them until then.

1. Create the Pages project once — either through Route A, or locally with
   `npx wrangler pages project create rareform`.
2. In Cloudflare: **My Profile → API Tokens → Create Token → Edit Cloudflare
   Workers**, or a custom token with:
   - **Account · Cloudflare Pages · Edit**
   - **Zone · DNS · Edit** (only if you want the token to manage DNS too)
3. In GitHub: **Settings → Secrets and variables → Actions → New repository
   secret**, twice:

   | Name | Where to find it |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token you just created |
   | `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard sidebar, or `npx wrangler whoami` |

4. Push anything under `rareform/`, or run the workflow manually from the
   **Actions** tab. The build log prints the deployed URL.

Do not commit the token. It only ever belongs in GitHub's secret store.

---

## 2. Point your own domain at it

`rareform.pages.dev` works immediately. To serve the site from your own domain:

**Cloudflare Pages → your project → Custom domains → Set up a domain.**

### If the domain's nameservers are already Cloudflare's

Type the domain and confirm. Cloudflare writes the DNS record itself and issues
the certificate. Nothing else to do — usually live within a minute.

### If the domain is registered elsewhere

Either move the nameservers to Cloudflare (**Websites → Add a site**, then set
the two nameservers Cloudflare gives you at your registrar), or add the records
yourself at your current DNS provider:

| Name | Type | Value | Proxy |
|---|---|---|---|
| `www` | `CNAME` | `rareform.pages.dev` | on, if on Cloudflare |
| `@` (apex) | `CNAME` | `rareform.pages.dev` | on |

An apex `CNAME` is not valid DNS at most providers. Cloudflare supports it via
CNAME flattening; elsewhere use whatever the provider calls `ALIAS` or `ANAME`,
or just move the nameservers to Cloudflare, which is the simpler path.

Cloudflare's custom-domain screen shows the exact record for your project —
follow that over this table if the two ever disagree, and expect DNS to take
anywhere from a minute to a few hours to propagate.

---

## 3. Opening the shop inside another site

Add `?embed=1` and drop it in an iframe. That flag hides the marquee and footer
and stops the header sticking, so the host page keeps control of the scroll.

```html
<iframe
  src="https://rareform.pages.dev/?embed=1"
  title="RAREFORM storefront"
  style="width:100%;height:820px;border:0"
  loading="lazy"
  allow="fullscreen"
></iframe>
```

`public/_headers` ships `Content-Security-Policy: frame-ancestors *`, which lets
any site embed it. Once you know which sites should be allowed, narrow it:

```
Content-Security-Policy: frame-ancestors https://your-site.example
```

Leaving it open means anyone can frame the page, admin panel included. Since the
admin sign-in is browser-side and protects nothing, that is not a new hole — but
it is one more reason to put real authentication in front of it.

---

## Notes for a real launch

- **The admin panel guards nothing.** Its sign-in runs in the browser. Anyone who
  reaches `/` can open it. Real server-side authentication has to come first.
- WebGL is required for the 3D renders. Without it the catalogue still works —
  cards fall back to flat colourway tiles.
- The bundle is one large JavaScript file, mostly three.js. Cloudflare serves it
  compressed, and `_headers` caches hashed assets for a year.
- Cloudflare Pages' free tier covers unlimited requests and bandwidth with 500
  builds a month, which is far more than this needs.
