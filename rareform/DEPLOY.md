# Deploying RAREFORM on your own domain

The site is a static build — no server, no database, no environment variables.
Anything that serves files will host it, and a custom domain is a DNS record away.

```bash
cd rareform
npm install
npm run build      # -> dist/
```

`dist/` is the whole site. `npm run bundle` additionally writes `dist/rareform.html`,
a single self-contained file if you would rather drop one page onto existing hosting.

## Hosting, then DNS

Pick one host. Each takes about two minutes.

### Cloudflare Pages

1. Create a project from this repository.
2. Root directory `rareform`, build command `npm run build`, output directory `dist`.
3. Add your domain under **Custom domains**. If the domain's nameservers are already
   Cloudflare's, the DNS record is created for you.

### Vercel

1. Import the repository and set the root directory to `rareform` — `vercel.json`
   supplies the rest.
2. **Settings → Domains → Add**, then create the records Vercel shows you:

   | Host | Type | Value |
   |---|---|---|
   | `@` | `A` | `76.76.21.21` |
   | `www` | `CNAME` | `cname.vercel-dns.com` |

### Netlify

1. Import the repository — `netlify.toml` already points at `rareform/dist`.
2. **Domain management → Add a domain**, then either delegate the domain to
   Netlify's nameservers or add a `CNAME` from `www` to your `*.netlify.app` name.

Verify the exact record values in your host's dashboard before you create them —
the addresses above are the current published defaults and hosts do change them.

## Notes for a real launch

- HTTPS is automatic on all three hosts; nothing in the app needs configuring.
- The build is one large JavaScript file, mostly three.js. Hosts serve it compressed;
  the caching header above keeps repeat visits instant.
- WebGL is required for the 3D renders. The page degrades to flat colourway tiles
  without it, so the catalogue still functions.
- The admin panel's sign-in runs entirely in the browser and protects nothing.
  Put real authentication in front of it before the site is public.
