import { useEffect, useRef, useState } from 'react'
import { garmentSpec } from '../data/catalog.js'
import { cachedThumbnail, requestThumbnail, thumbnailSupported } from '../three/thumbnails.js'
import { highlight } from '../search/engine.js'
import { money } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

function Highlighted({ text, query }) {
  if (!query) return text
  return highlight(text, query).map((part, index) =>
    part.hit ? <mark key={index}>{part.text}</mark> : <span key={index}>{part.text}</span>)
}

export function GarmentImage({ product, colorway, angle = -0.42, alt, className = 'card__img' }) {
  const spec = garmentSpec(product, colorway, angle)
  const [src, setSrc] = useState(() => cachedThumbnail(spec))
  const holderRef = useRef(null)
  const [seen, setSeen] = useState(() => Boolean(cachedThumbnail(spec)))

  useEffect(() => {
    if (seen || !holderRef.current) return undefined
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) {
        setSeen(true)
        observer.disconnect()
      }
    }, { rootMargin: '320px' })
    observer.observe(holderRef.current)
    return () => observer.disconnect()
  }, [seen])

  useEffect(() => {
    const cached = cachedThumbnail(spec)
    if (cached) {
      setSrc(cached)
      return undefined
    }
    setSrc(null)
    if (!seen) return undefined
    let alive = true
    requestThumbnail(spec).then(url => { if (alive) setSrc(url) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spec.kind, spec.fit, spec.fabric, spec.seed, spec.color, spec.accent, spec.angle, seen])

  return (
    <span ref={holderRef} style={{ display: 'block', width: '100%', height: '100%', position: 'relative' }}>
      {src
        ? <img className={className} src={src} alt={alt ?? `${product.name} in ${colorway.name}`} loading="lazy" />
        : (
          <span className="card__skeleton" aria-hidden="true">
            {!thumbnailSupported() && (
              <span
                style={{
                  position: 'absolute', inset: '18%', borderRadius: 6,
                  background: `linear-gradient(160deg, ${colorway.hex}, ${colorway.accent})`,
                }}
              />
            )}
          </span>
        )}
    </span>
  )
}

export default function ProductCard({
  product, query = '', wished, onWish, onOpen, onQuickAdd, activeColorIndex, onColorChange,
}) {
  const [localColor, setLocalColor] = useState(0)
  const index = activeColorIndex ?? localColor
  const colorway = product.colorways[Math.min(index, product.colorways.length - 1)]
  const discount = product.compareAt ? Math.round((1 - product.price / product.compareAt) * 100) : 0

  const setColor = next => {
    setLocalColor(next)
    onColorChange?.(next)
  }

  return (
    <article className="card">
      <button type="button" className="card__stage" onClick={() => onOpen(product, index)} aria-label={`View ${product.name}`}>
        <GarmentImage product={product} colorway={colorway} />
      </button>

      <div className="card__flags">
        {product.badge && <span className="tag tag--signal">{product.badge}</span>}
        {discount > 0 && <span className="tag tag--sale">−{discount}%</span>}
        {product.sustainable && <span className="tag tag--eco">Responsible</span>}
        {product.stock <= 8 && <span className="tag">Low stock</span>}
      </div>

      <button
        type="button" className="card__wish" aria-pressed={wished}
        aria-label={wished ? `Remove ${product.name} from wishlist` : `Save ${product.name} to wishlist`}
        onClick={() => onWish(product)}
      >
        <Icon name="heart" size={16} fill={wished ? 'currentColor' : 'none'} />
      </button>

      <div className="card__quick">
        {product.sizes.slice(0, product.sizeType === 'one' ? 1 : 5).map(size => (
          <button
            key={size} type="button"
            onClick={() => onQuickAdd(product, size, colorway)}
            disabled={product.stock <= 0}
            aria-label={`Add ${product.name}, size ${size}, to bag`}
          >
            {size}
          </button>
        ))}
      </div>

      <div className="card__body">
        <span className="card__cat">{product.categoryLabel} · {product.department}</span>
        <h3 className="card__name"><Highlighted text={product.name} query={query} /></h3>
        <div className="card__meta">
          <span className="card__price">{money(product.price)}</span>
          {product.compareAt && <span className="card__was">{money(product.compareAt)}</span>}
          <span style={{ marginLeft: 'auto', display: 'inline-flex', alignItems: 'center', gap: 4, color: 'var(--text-3)', fontSize: 11 }}>
            <Icon name="star" size={11} fill="currentColor" />
            {product.rating.toFixed(1)}
          </span>
        </div>
        <div className="card__swatches">
          {product.colorways.map((cw, i) => (
            <button
              key={cw.name} type="button" className="card__swatch"
              style={{ background: cw.hex }} aria-pressed={i === index}
              aria-label={`Show ${cw.name}`} title={cw.name}
              onClick={() => setColor(i)}
            />
          ))}
        </div>
      </div>
    </article>
  )
}
