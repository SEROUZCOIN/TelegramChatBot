import { useEffect, useMemo, useRef, useState } from 'react'
import { suggest } from '../search/engine.js'
import { CATEGORIES, COLLECTIONS } from '../data/catalog.js'
import { useFocusTrap, useLockBody, money } from '../lib/store.js'
import { GarmentImage } from './ProductCard.jsx'
import { Icon } from '../lib/icons.jsx'
import { highlight } from '../search/engine.js'

function Marked({ text, query }) {
  return highlight(text, query).map((part, i) => (part.hit ? <mark key={i}>{part.text}</mark> : <span key={i}>{part.text}</span>))
}

export default function CommandPalette({ open, index, recents, onClose, onSearch, onOpenProduct, onCategory, onCollection }) {
  const [value, setValue] = useState('')
  const [cursor, setCursor] = useState(0)
  const panelRef = useRef(null)
  const inputRef = useRef(null)

  useLockBody(open)
  useFocusTrap(open, panelRef)

  useEffect(() => {
    if (open) {
      setValue('')
      setCursor(0)
      requestAnimationFrame(() => inputRef.current?.focus())
    }
  }, [open])

  const rows = useMemo(() => {
    if (!open) return []
    if (!value.trim()) {
      return [
        ...recents.slice(0, 4).map(term => ({ kind: 'recent', id: `r-${term}`, label: term })),
        ...COLLECTIONS.map(col => ({ kind: 'collection', id: col.id, label: col.label })),
        ...CATEGORIES.slice(0, 6).map(cat => ({ kind: 'category', id: cat.id, label: cat.label, sub: cat.group })),
      ]
    }
    const hits = suggest(index, value, 8)
    return [
      { kind: 'query', id: 'q', label: value },
      ...hits.map(hit => ({
        kind: hit.type === 'product' ? 'product' : 'category',
        id: hit.id,
        label: hit.label,
        sub: hit.sub,
        product: hit.product,
      })),
    ]
  }, [open, value, index, recents])

  useEffect(() => { setCursor(0) }, [value])

  const run = row => {
    if (!row) return
    if (row.kind === 'product') onOpenProduct(row.product)
    else if (row.kind === 'category') onCategory(row.id)
    else if (row.kind === 'collection') onCollection(row.id)
    else onSearch(row.label)
    onClose()
  }

  const onKeyDown = event => {
    if (event.key === 'Escape') { onClose(); return }
    if (event.key === 'ArrowDown') { event.preventDefault(); setCursor(c => Math.min(c + 1, rows.length - 1)) }
    if (event.key === 'ArrowUp') { event.preventDefault(); setCursor(c => Math.max(c - 1, 0)) }
    if (event.key === 'Enter') { event.preventDefault(); run(rows[cursor]) }
  }

  if (!open) return null

  let lastKind = null

  return (
    <>
      <div className="scrim" onClick={onClose} />
      <div className="palette-wrap" role="dialog" aria-modal="true" aria-label="Search RAREFORM">
        <div className="palette" ref={panelRef} onKeyDown={onKeyDown}>
          <div className="palette__field">
            <Icon name="search" size={19} />
            <input
              ref={inputRef} value={value} onChange={e => setValue(e.target.value)}
              placeholder="Search garments, categories, fabrics…" aria-label="Search"
              autoComplete="off" spellCheck="false"
            />
            <button type="button" className="icon-btn" onClick={onClose} aria-label="Close search">
              <Icon name="x" size={17} />
            </button>
          </div>

          <div className="palette__body">
            {rows.length === 0 && (
              <p style={{ padding: 28, textAlign: 'center', color: 'var(--text-2)' }}>
                Nothing matched “{value}”. Try a category, fabric or colour.
              </p>
            )}
            {rows.map((row, i) => {
              const heading = row.kind !== lastKind
                ? { query: 'Search', recent: 'Recent', collection: 'Collections', category: 'Categories', product: 'Garments' }[row.kind]
                : null
              lastKind = row.kind
              return (
                <div key={`${row.kind}-${row.id}`}>
                  {heading && <div className="palette__group">{heading}</div>}
                  <button
                    type="button" className="palette__row" data-active={i === cursor}
                    onMouseEnter={() => setCursor(i)} onClick={() => run(row)}
                  >
                    {row.kind === 'product' && row.product
                      ? (
                        <span className="palette__thumb" style={{ overflow: 'hidden' }}>
                          <GarmentImage product={row.product} colorway={row.product.colorways[0]} className="card__img" />
                        </span>
                      )
                      : (
                        <span className="palette__thumb" style={{ display: 'grid', placeItems: 'center', height: 34, width: 34 }}>
                          <Icon name={{ query: 'search', recent: 'clock', collection: 'sparkle', category: 'grid' }[row.kind]} size={16} />
                        </span>
                      )}
                    <span style={{ minWidth: 0 }}>
                      <strong>
                        {row.kind === 'query' ? <>Search for “{row.label}”</> : <Marked text={row.label} query={value} />}
                      </strong>
                      {row.sub && <span>{row.sub}</span>}
                    </span>
                    {row.product && <em>{money(row.product.price)}</em>}
                    {!row.product && <em><Icon name="corner" size={13} /></em>}
                  </button>
                </div>
              )
            })}
          </div>

          <div className="palette__foot">
            <span><kbd>↑</kbd> <kbd>↓</kbd> navigate</span>
            <span><kbd>↵</kbd> open</span>
            <span><kbd>esc</kbd> close</span>
            <span style={{ marginLeft: 'auto' }}>Typo-tolerant across name, fabric, colour and SKU</span>
          </div>
        </div>
      </div>
    </>
  )
}
