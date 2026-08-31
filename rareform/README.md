# RAREFORM — rendered clothing marketplace

A clothing storefront with no product photography. Every garment in the catalogue is
built as real 3D geometry at runtime, lit in a virtual studio and rendered by WebGL —
the grid thumbnails, the product page viewer and the bag line items all come out of the
same renderer.

```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # dist/
npm run bundle     # dist/rareform.html — one self-contained file, no external assets
```

## What's in it

**Live 3D across 15 categories** — t-shirts, shirts, hoodies, knitwear, jackets, coats,
trousers, denim, shorts, dresses, skirts, footwear, headwear, bags and accessories.
Seventeen garment builders loft each piece from parametric cross-sections, then displace
the surface with layered noise so cloth creases and drapes instead of looking moulded.
Fabric normal and roughness maps (twill, rib, wale, ripstop, grain) are drawn from height
functions at load time, so the repository contains no image files at all.

**Product cards are renders, not photos.** An off-screen WebGL renderer draws each
colourway on demand — queued a couple per frame, cached as data URLs, requested only when
a card comes near the viewport. Changing the swatch on a card re-renders that garment in
the new colour.

**Search that tolerates a typo.** Weighted field matching over name, category, tags,
fabric, colour, fit, description and SKU, with a bounded edit distance so `jaket`,
`selvage` and `dres` all land. `⌘K` (or `/`) opens a command palette with grouped
suggestions, recent searches and keyboard navigation.

**Faceted filtering with honest counts.** Each facet is counted against every filter
except its own dimension, so the number beside a filter is what you would actually get by
selecting it. Filters, sort, chips, bag, wishlist and theme all persist to local storage.

**A spatial viewer, not a spinner.** Product pages sit in a lit void with a receding
grid floor and bloom post-processing, and carry a live telemetry read-out — triangle
count, frame rate, shading mode. **X-ray** drops the garment to wireframe so you can see
how it is actually constructed: the hood panels, the sleeve loft, the pocket, the yoke.
Five scene presets: Studio, Obsidian, Daylight, Hologram, Noir.

**The rest of the shop.** Size guides per size system, quick-add from the grid, a bag
drawer with free-shipping progress and promo codes, a three-step demo checkout, light and
dark themes, and a mobile layout where the filter rail becomes a sheet.

**An admin panel wired to all of it.** Sign in from the header. Seven sections:

- **Overview** — revenue, orders, average order value and refunds, a 28-day revenue chart
  with the current week called out, low-stock alerts and top garments by revenue.
- **Products** — the full catalogue with search and category filter. The editor renders
  the garment it is describing, live: change the model, fit, fabric or a colourway hex and
  the 3D preview rebuilds as you type. Create, edit and delete.
- **Orders** — expandable line items, status pipeline from Pending through Delivered.
- **Inventory** — stock levels with adjustment controls and a low-stock filter.
- **Customers** — ranked by lifetime spend.
- **3D Studio** — scene presets for product pages and for catalogue cards, presentation
  angle, exposure, bloom strength, grid floor and auto-rotate. Changing the card scene
  clears the render cache so every card redraws at the new lighting.
- **Settings** — store name, currency, shipping thresholds, returns window, low-stock
  threshold and promo codes.

Admin and storefront share one store, so a rename, a price change, a new colourway, a
currency switch or a promo code lands on the shop immediately. Checkout writes a real
order into the admin panel and decrements stock.

## Layout

| Path | What it holds |
|---|---|
| `src/three/loft.js` | Superellipse lofting, path lofting, cloth drape displacement |
| `src/three/garments.js` | The 17 garment builders and the colourway recolour pass |
| `src/three/materials.js` | Procedural fabric normal/roughness maps and material presets |
| `src/three/studio.js` | Renderer, three-point lighting, five scene presets, backdrop, grid |
| `src/three/effects.js` | Bloom composer, X-ray construction view, triangle counting |
| `src/three/thumbnails.js` | Off-screen render queue and data-URL cache for cards |
| `src/search/engine.js` | Tokenising, fuzzy scoring, facet counting, suggestions |
| `src/data/catalog.js` | The catalogue — each product carries its own garment spec |
| `src/components/` | Header, hero, grid, filters, product page, bag, palette, checkout |
| `src/store/ShopContext.jsx` | The single store behind both the shop and the admin panel |
| `src/admin/` | Admin shell, the seven screens and the live product editor |
| `src/styles/app.css` | Design tokens and the storefront component system |
| `src/styles/admin.css` | The denser admin console layer |

## Admin access

Open it from the person icon in the header or **Admin control panel** in the footer.

```
admin@rareform.studio
admin123
```

That check runs in the browser and guards nothing. Put real server-side authentication
in front of it before this goes anywhere public.

## Deploying

See [DEPLOY.md](DEPLOY.md) — `npm run build` produces a static `dist/`, and `vercel.json`
and `netlify.toml` are already set up. The same file covers pointing a custom domain at it.

## Notes

This is a front-end demonstration. There is no server, no payment provider and no real
inventory — the checkout takes nothing and ships nothing. Adding a product means adding a
row to `src/data/catalog.js`; its `kind`, `fit`, `fabric` and colourway hexes are fed
straight into the garment builder, and the 3D model follows.

Requires WebGL. Without it the page still works — cards fall back to a flat colourway
tile and the viewer explains what is missing.
