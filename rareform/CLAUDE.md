# RAREFORM — project guide

## What this is

A clothing marketplace front end where the product imagery is generated, not stored.
React + Vite + three.js; no backend, no image assets.

## Commands

```bash
npm install
npm run dev
npm run build
npm run bundle   # single-file build at dist/rareform.html
```

Run `npm run build` after any meaningful change — it is the only type of check this
project has.

## How the rendering works

1. `src/data/catalog.js` describes each product, including a garment `kind`, `fit`,
   `fabric`, `seed` and a list of colourways.
2. `garmentSpec(product, colorway)` turns that into a spec.
3. `src/three/garments.js` builds a `THREE.Group` from the spec. Every mesh is tagged
   with `userData.slot` (`body`, `accent`, `trim`, `hardware`, `sole`, `interior`) so
   `recolorGarment()` can change colourway without rebuilding geometry.
4. `buildGarment()` centres the result and normalises it to a fixed height, so every
   garment drops into the same camera framing.
5. `src/three/thumbnails.js` renders specs off-screen into cached data URLs for cards;
   `src/components/Viewer3D.jsx` renders the same spec interactively.

Geometry comes from `src/three/loft.js`: `loftSections` stacks superellipse
cross-sections vertically, `loftAlongPath` sweeps one along a curve (sleeves, legs,
hoods, straps), and `drapeCloth` displaces vertices along their normals with layered
noise plus vertical folds.

## Rules for changes here

1. Do not add image files. If a product needs a look, express it as geometry, fabric or
   colour — the "no photography" premise is the point of the project.
2. Keep meshes tagged with a `slot`, or colourway switching will silently skip them.
3. Presentation rotation belongs to the viewer (`spec.angle`), never baked into a
   builder — baking it in rotates the model twice and corrupts its bounding box.
4. Anything lofted along a nearly straight path needs its profile checked against the
   Frenet frame; `w` follows the curve normal, `d` the binormal, and they swap meaning
   when the path direction changes.
5. Preserve keyboard access, visible focus, `aria-pressed` state, dialog semantics and
   `prefers-reduced-motion` handling.
6. Facet counts must keep excluding their own dimension (`passesFilters(…, skip)`),
   otherwise every count collapses to the current result set.
7. Both themes are defined token-level: the bare `:root` block holds the light palette,
   and the dark palette is repeated in a `prefers-color-scheme` block and a
   `[data-theme='dark']` block. Never define a colour in only one of them.

## Verifying a change

Geometry problems are much easier to see numerically than in a screenshot. Build a
garment in Node (the material code no-ops without a DOM) and print bounding boxes —
a garment that is wider than it is tall, or whose depth approaches its width, is
usually a rotation or profile-axis bug rather than a lighting one.

## If this ever gets a backend

Replace local storage with real services: authentication, a product/inventory database,
cloud order handling, a payment provider, tax and shipping. Treat everything currently
in `usePersistentState` as demonstration state.
