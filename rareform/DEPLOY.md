# Deploying RAREFORM

The site is a static build — no server, no database, no environment variables.
Two free hosts are wired up: GitHub Pages, which needs nothing but this
repository, and Cloudflare Pages, which is the one to use for a custom domain.

```bash
cd rareform
npm install
npm run build      # -> dist/   (this is the whole site)
npm run bundle     # -> dist/rareform.html, one self-contained file
```

Everything below is already committed: `wrangler.toml`, `public/_headers`,
`public/_redirects`, and a GitHub Actions workflow.

---

## 0. GitHub Pages — the quickest public URL

The repository is public, so GitHub Pages is free and needs no other account.
`.github/workflows/deploy-rareform.yml` already builds and publishes to it on
every push that touches `rareform/`, with the base path set to the repository
name so assets resolve under the subpath.

**One switch first.** A workflow token is not allowed to create a Pages site,
so turn it on once by hand:

**Settings → Pages → Build and deployment → Source → GitHub Actions.**

Then re-run the workflow from the **Actions** tab, or push anything under
`rareform/`. Until Pages is on, the job checks, prints a notice and passes
without publishing — it never fails the build.

Once it publishes, the site is at:

```
https://serouzcoin.github.io/TelegramChatBot/
```

Open it from any PC or phone — no sign-in, nothing to install. Every later push
that touches `rareform/` republishes it.

### Your own domain on GitHub Pages

You need to own the domain first — buy it from any registrar (Namecheap,
Cloudflare Registrar, Porkbun, GoDaddy). Nothing here can register one for you.

Once you own it, two steps:

1. **Settings → Secrets and variables → Actions → Variables → New variable**

   | Name | Value |
   |---|---|
   | `PAGES_CUSTOM_DOMAIN` | `example.com` |

   The build reads it, switches the base path to the domain root and writes the
   `CNAME` file. Without it the site keeps publishing to the repository subpath.

2. At your DNS provider, point the domain at GitHub:

   | Name | Type | Value |
   |---|---|---|
   | `@` | `A` | `185.199.108.153` |
   | `@` | `A` | `185.199.109.153` |
   | `@` | `A` | `185.199.110.153` |
   | `@` | `A` | `185.199.111.153` |
   | `www` | `CNAME` | `serouzcoin.github.io` |

   For a subdomain only (`shop.example.com`), skip the `A` records and use a
   single `CNAME` to `serouzcoin.github.io`.

Then push, or re-run the workflow. Confirm the records against **Settings →
Pages → Custom domain**, which validates them and issues the certificate —
follow that screen over this table if they disagree. Tick **Enforce HTTPS**
once the certificate is ready.

---

## 1. Cloudflare Pages

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
