# RAREFORM design system

## Principles

1. **The garment is the interface.** The 3D render is the largest, quietest element on
   every surface. Chrome sits at the edges of it, never on top of it.
2. **One signal colour.** Chartreuse marks primary actions, selected state and live
   system feedback. Nothing else competes for it.
3. **Technical, not decorative.** Depth comes from scale, lighting and rules — monospace
   metadata, hairline borders, generous negative space.
4. **Inclusive by default.** Visible focus, keyboard operation, dialog semantics,
   reduced-motion support, 44px customer-facing targets, never colour alone for state.

## Type

| Role | Face | Use |
|---|---|---|
| Display | Archivo 700–900 | Headlines, product names, buttons, section heads |
| Body | Inter 400–600 | Descriptions, form copy, list content |
| Utility | JetBrains Mono 400–500 | Metadata, counts, prices, facet labels, SKUs |

Uppercase runs carry `0.06–0.18em` letter-spacing. Headings use `text-wrap: balance`.
Anywhere digits stack in a column uses `tabular-nums`.

## Colour

Tokens are defined once on `:root` as the light palette and redefined — token for token —
in both a `prefers-color-scheme: dark` block and a `[data-theme='dark']` block, so the
page resolves correctly whether the host states a theme or not.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f4f2ec` | `#0b0c0b` | Page ground |
| `--surface` | `#ffffff` | `#131513` | Cards, drawers, panels |
| `--surface-3` | `#eeebe2` | `#232622` | Hover and pressed fills |
| `--text` | `#14161a` | `#f0f2ea` | Primary copy |
| `--text-2` / `--text-3` | `#55595c` / `#86898a` | `#a4a99f` / `#767a72` | Support and metadata |
| `--line` | 13% ink | 14% bone | Dividers and quiet outlines |
| `--accent` | `#1c1e22` | `#eef2e4` | Primary button surface |
| `--signal` | `#b7e21b` | `#ceff25` | Selected state, live indicators, checkout |
| `--danger` / `--positive` | `#b8442f` / `#2f6b45` | `#ff7c68` / `#8fd6a4` | Sale, errors / savings, eco |

The signal green is darkened in the light theme so it holds contrast on a paper ground.

## Motion

`--fast 150ms` for focus and small state changes, `--base 300ms` for cards, drawers and
overlays, `--slow 620ms` for image scale and progress. Everything eases on
`cubic-bezier(.16, 1, .3, 1)`. Under `prefers-reduced-motion` all animation, the marquee
and the viewer's auto-rotation stop.

## Components

**Buttons** — one primary per decision area. Primary is the accent surface; signal is
reserved for checkout and live confirmations. Icon-only buttons carry an accessible name.

**Product cards** — the render area is a button that opens the product. Wishlist uses
`aria-pressed` with a state-specific label. Name, colour count and price stay visible
without hover; quick-add sizes appear on hover and are always visible on touch.

**Filters** — every facet exposes `aria-pressed` and a count computed excluding its own
dimension. Active filters also appear as removable chips above the grid. Result count
updates through a polite live region.

**Overlays** — the palette, bag, size guide and checkout are dialogs: they trap focus,
close on Escape, lock background scroll and return focus to their opener.

**The 3D stage** — a `--stage` gradient behind every render, in both themes, so a
transparent garment render sits on a consistent ground. HUD chips float over the canvas
with a blurred surface and never cover the garment's centre.
