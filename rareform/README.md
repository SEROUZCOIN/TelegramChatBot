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

**The rest of the shop.** Product pages with a draggable viewer and four studio lighting
presets, size guides per size system, quick-add from the grid, a bag drawer with
free-shipping progress and promo codes, a three-step demo checkout, light and dark themes,
and a mobile layout where the filter rail becomes a sheet.

## Layout

| Path | What it holds |
|---|---|
| `src/three/loft.js` | Superellipse lofting, path lofting, cloth drape displacement |
| `src/three/garments.js` | The 17 garment builders and the colourway recolour pass |
| `src/three/materials.js` | Procedural fabric normal/roughness maps and material presets |
| `src/three/studio.js` | Renderer, three-point lighting, scene presets, camera |
| `src/three/thumbnails.js` | Off-screen render queue and data-URL cache for cards |
| `src/search/engine.js` | Tokenising, fuzzy scoring, facet counting, suggestions |
| `src/data/catalog.js` | The catalogue — each product carries its own garment spec |
| `src/components/` | Header, hero, grid, filters, product page, bag, palette, checkout |
| `src/styles/app.css` | Design tokens and the full component system |

## Notes

This is a front-end demonstration. There is no server, no payment provider and no real
inventory — the checkout takes nothing and ships nothing. Adding a product means adding a
row to `src/data/catalog.js`; its `kind`, `fit`, `fabric` and colourway hexes are fed
straight into the garment builder, and the 3D model follows.

Requires WebGL. Without it the page still works — cards fall back to a flat colourway
tile and the viewer explains what is missing.
