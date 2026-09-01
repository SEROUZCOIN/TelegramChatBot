import { useState } from 'react'
import { CATEGORIES, CATEGORY_GROUPS, COLOR_FAMILIES, COLLECTIONS, DEPARTMENTS, SIZE_SETS } from '../data/catalog.js'
import { FABRICS } from '../three/materials.js'
import { money } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

const FITS = ['slim', 'regular', 'relaxed', 'oversized', 'cropped']
const ALL_SIZES = [...new Set([...SIZE_SETS.apparel, ...SIZE_SETS.waist, ...SIZE_SETS.shoe, ...SIZE_SETS.one])]

function Facet({ title, children, defaultOpen = true }) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <section className="facet">
      <button type="button" className="facet__head" aria-expanded={open} onClick={() => setOpen(v => !v)}>
        {title}
        <Icon name={open ? 'chevronUp' : 'chevronDown'} size={14} />
      </button>
      {open && <div className="facet__body">{children}</div>}
    </section>
  )
}

function Row({ label, count, active, onToggle, swatch }) {
  const disabled = !count && !active
  return (
    <button
      type="button" className="facet__row" aria-pressed={active} onClick={onToggle}
      disabled={disabled} style={disabled ? { opacity: 0.38, cursor: 'not-allowed' } : undefined}
    >
      {swatch
        ? <span className="facet__swatch" style={{ background: swatch }} />
        : <span className="facet__box">{active && <Icon name="check" size={11} strokeWidth={2.6} />}</span>}
      <span>{label}</span>
      <span className="facet__count">{count ?? 0}</span>
    </button>
  )
}

export default function FilterRail({ facets, filters, setFilters, bounds, resultCount, open, onClose, onClear }) {
  const toggle = (key, value) => setFilters(current => {
    const list = current[key]
    return { ...current, [key]: list.includes(value) ? list.filter(v => v !== value) : [...list, value] }
  })

  const price = filters.price ?? [bounds.min, bounds.max]

  return (
    <aside className="rail" data-open={open} aria-label="Filters">
      <div className="rail__inner">
        <div className="rail__head mobile-only">
          <h2 style={{ flex: 1, fontSize: 15, textTransform: 'uppercase', letterSpacing: '0.06em' }}>Filters</h2>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close filters"><Icon name="x" /></button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingBottom: 8 }}>
          <span className="mono" style={{ color: 'var(--text-3)' }}>Refine</span>
          <button type="button" className="btn btn--ghost btn--sm" onClick={onClear}>Clear all</button>
        </div>

        <Facet title="Collection">
          {COLLECTIONS.map(col => (
            <Row
              key={col.id} label={col.label} count={facets.collections.get(col.id)}
              active={filters.collections.includes(col.id)} onToggle={() => toggle('collections', col.id)}
            />
          ))}
        </Facet>

        <Facet title="Department">
          {DEPARTMENTS.map(dep => (
            <Row
              key={dep} label={dep} count={facets.departments.get(dep)}
              active={filters.departments.includes(dep)} onToggle={() => toggle('departments', dep)}
            />
          ))}
        </Facet>

        <Facet title="Category">
          {CATEGORY_GROUPS.map(group => (
            <div key={group}>
              <div className="mono" style={{ color: 'var(--text-3)', padding: '10px 0 4px', fontSize: 9.5 }}>{group}</div>
              {CATEGORIES.filter(cat => cat.group === group).map(cat => (
                <Row
                  key={cat.id} label={cat.label} count={facets.categories.get(cat.id)}
                  active={filters.categories.includes(cat.id)} onToggle={() => toggle('categories', cat.id)}
                />
              ))}
            </div>
          ))}
        </Facet>

        <Facet title="Size">
          <div className="sizegrid">
            {ALL_SIZES.map(size => {
              const count = facets.sizes.get(size) ?? 0
              const active = filters.sizes.includes(size)
              return (
                <button
                  key={size} type="button" aria-pressed={active} disabled={!count && !active}
                  onClick={() => toggle('sizes', size)} title={`${count} garments`}
                  style={size === 'One size' ? { gridColumn: 'span 2' } : undefined}
                >
                  {size}
                </button>
              )
            })}
          </div>
        </Facet>

        <Facet title="Colour">
          {COLOR_FAMILIES.map(family => (
            <Row
              key={family.id} label={family.label} count={facets.colors.get(family.id)}
              active={filters.colors.includes(family.id)} onToggle={() => toggle('colors', family.id)}
              swatch={family.swatch}
            />
          ))}
        </Facet>

        <Facet title="Fabric" defaultOpen={false}>
          {Object.keys(FABRICS).filter(key => facets.fabrics.has(key) || filters.fabrics.includes(key)).map(key => (
            <Row
              key={key} label={key[0].toUpperCase() + key.slice(1)} count={facets.fabrics.get(key)}
              active={filters.fabrics.includes(key)} onToggle={() => toggle('fabrics', key)}
            />
          ))}
        </Facet>

        <Facet title="Fit" defaultOpen={false}>
          {FITS.map(fit => (
            <Row
              key={fit} label={fit[0].toUpperCase() + fit.slice(1)} count={facets.fits.get(fit)}
              active={filters.fits.includes(fit)} onToggle={() => toggle('fits', fit)}
            />
          ))}
        </Facet>

        <Facet title="Price">
          <div className="range">
            <span className="range__value">{money(bounds.min)}</span>
            <input
              type="range" min={bounds.min} max={bounds.max} step={5} value={price[1]}
              aria-label={`Maximum price, currently ${money(price[1])}`}
              onChange={e => setFilters(c => ({ ...c, price: [bounds.min, Number(e.target.value)] }))}
            />
            <span className="range__value">{money(price[1])}</span>
          </div>
        </Facet>

        <Facet title="Availability">
          <Row
            label="In stock only" count={resultCount} active={filters.inStockOnly}
            onToggle={() => setFilters(c => ({ ...c, inStockOnly: !c.inStockOnly }))}
          />
          <Row
            label="Responsible materials" count={facets.collections.get('sustainable')} active={filters.sustainableOnly}
            onToggle={() => setFilters(c => ({ ...c, sustainableOnly: !c.sustainableOnly }))}
          />
        </Facet>

        <div className="rail__apply mobile-only" style={{ marginTop: 20 }}>
          <button type="button" className="btn btn--primary btn--block" onClick={onClose}>
            Show {resultCount} {resultCount === 1 ? 'garment' : 'garments'}
          </button>
        </div>
      </div>
    </aside>
  )
}
