import { useMemo, useState } from 'react'
import Viewer3D from './Viewer3D.jsx'
import ProductCard from './ProductCard.jsx'
import SizeGuide from './SizeGuide.jsx'
import { garmentSpec } from '../data/catalog.js'
import { useShop } from '../store/ShopContext.jsx'
import { money } from '../lib/store.js'
import { Icon, Stars } from '../lib/icons.jsx'

function Accordion({ items }) {
  const [open, setOpen] = useState(items[0]?.title ?? null)
  return (
    <div className="accordion">
      {items.map(item => (
        <div className="accordion__item" key={item.title}>
          <button
            type="button" className="accordion__head" aria-expanded={open === item.title}
            onClick={() => setOpen(open === item.title ? null : item.title)}
          >
            {item.title}
            <Icon name={open === item.title ? 'minus' : 'plus'} size={15} />
          </button>
          {open === item.title && <div className="accordion__body">{item.body}</div>}
        </div>
      ))}
    </div>
  )
}

export default function ProductPage({ product, initialColor = 0, wished, onWish, onAdd, onBack, onOpenProduct }) {
  const { products, settings, studio } = useShop()
  const [colorIndex, setColorIndex] = useState(Math.min(initialColor, product.colorways.length - 1))
  const [size, setSize] = useState(product.sizeType === 'one' ? product.sizes[0] : null)
  const [qty, setQty] = useState(1)
  const [guide, setGuide] = useState(false)
  const [error, setError] = useState(false)

  const colorway = product.colorways[colorIndex]
  const spec = garmentSpec(product, colorway, studio.angle)

  const related = useMemo(() => products
    .filter(p => p.id !== product.id && (p.category === product.category || p.tags.some(t => product.tags.includes(t))))
    .sort((a, b) => b.popularity - a.popularity)
    .slice(0, 4), [product, products])

  const submit = () => {
    if (!size) {
      setError(true)
      return
    }
    setError(false)
    onAdd(product, size, colorway, qty)
  }

  const discount = product.compareAt ? Math.round((1 - product.price / product.compareAt) * 100) : 0

  return (
    <div className="shell">
      <nav className="pdp__crumbs mono" aria-label="Breadcrumb">
        <button type="button" onClick={onBack}>Shop</button>
        <Icon name="chevronRight" size={12} />
        <span>{product.categoryLabel}</span>
        <Icon name="chevronRight" size={12} />
        <span style={{ color: 'var(--text)' }}>{product.name}</span>
      </nav>

      <div className="pdp">
        <div className="pdp__stage">
          <Viewer3D
            spec={spec} label={`${product.name} in ${colorway.name}`}
            autoRotate={studio.autoRotate} preset={studio.preset} showTelemetry
            bloom={studio.bloom} bloomStrength={studio.bloomStrength}
            grid={studio.grid} exposure={studio.exposure}
          />
        </div>

        <div>
          <span className="mono muted">{product.sku} · {product.department} · {product.categoryLabel}</span>
          <h1>{product.name}</h1>

          <div className="pdp__price">
            <strong>{money(product.price)}</strong>
            {product.compareAt && <s>{money(product.compareAt)}</s>}
            {discount > 0 && <span className="tag tag--sale">−{discount}%</span>}
          </div>

          <div className="pdp__rating">
            <Stars value={product.rating} size={13} />
            <span>{product.rating.toFixed(1)}</span>
            <span className="muted">({product.reviews} reviews)</span>
            {product.stock <= 8 && <span className="tag" style={{ marginLeft: 6 }}>Only {product.stock} left</span>}
          </div>

          <p className="pdp__desc">{product.description}</p>

          <div className="pdp__block">
            <div className="pdp__label">
              <span>Colour</span>
              <strong>{colorway.name}</strong>
            </div>
            <div className="swatchrow">
              {product.colorways.map((cw, index) => (
                <button
                  key={cw.name} type="button" aria-pressed={index === colorIndex}
                  aria-label={`Colour ${cw.name}`} title={cw.name}
                  style={{ background: cw.hex }} onClick={() => setColorIndex(index)}
                />
              ))}
            </div>
          </div>

          <div className="pdp__block">
            <div className="pdp__label">
              <span>Size</span>
              <button type="button" onClick={() => setGuide(true)}>Size guide</button>
            </div>
            <div className="sizerow">
              {product.sizes.map(value => (
                <button
                  key={value} type="button" aria-pressed={size === value}
                  onClick={() => { setSize(value); setError(false) }}
                >
                  {value}
                </button>
              ))}
            </div>
            {error && <p style={{ color: 'var(--danger)', fontSize: 13, marginTop: 10 }} role="alert">Choose a size first.</p>}
          </div>

          <div className="pdp__buy">
            <div className="qty" style={{ marginTop: 0, height: 44 }}>
              <button type="button" onClick={() => setQty(q => Math.max(1, q - 1))} aria-label="Decrease quantity" style={{ height: 42, width: 40 }}>
                <Icon name="minus" size={14} />
              </button>
              <span>{qty}</span>
              <button type="button" onClick={() => setQty(q => Math.min(9, q + 1))} aria-label="Increase quantity" style={{ height: 42, width: 40 }}>
                <Icon name="plus" size={14} />
              </button>
            </div>
            <button type="button" className="btn btn--primary" onClick={submit}>
              Add to bag — {money(product.price * qty)}
            </button>
            <button
              type="button" className="btn icon-btn" aria-pressed={wished} style={{ width: 48, minHeight: 44 }}
              aria-label={wished ? 'Remove from wishlist' : 'Save to wishlist'} onClick={() => onWish(product)}
            >
              <Icon name="heart" size={17} fill={wished ? 'currentColor' : 'none'} />
            </button>
          </div>

          <div className="pdp__notes">
            <p className="pdp__note"><Icon name="cube" size={15} /> Rendered live in your browser — drag the model to inspect the cut, seams and drape from any angle.</p>
            <p className="pdp__note">
              <Icon name="truck" size={15} /> Free shipping over {money(settings.freeShippingOver)}. Delivered in 2–4 working days.
            </p>
            <p className="pdp__note">
              <Icon name="refresh" size={15} /> {settings.returnsWindow}-day returns, no questions.
            </p>
            {product.sustainable && <p className="pdp__note"><Icon name="leaf" size={15} /> Made with responsibly sourced materials.</p>}
          </div>

          <dl className="specs">
            <div><dt>Fabric</dt><dd>{product.materialLabel}</dd></div>
            <div><dt>Fit</dt><dd style={{ textTransform: 'capitalize' }}>{product.fit}</dd></div>
            <div><dt>Category</dt><dd>{product.categoryLabel}</dd></div>
            <div><dt>Released</dt><dd>{new Date(product.releasedAt).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' })}</dd></div>
          </dl>

          <Accordion
            items={[
              { title: 'Construction', body: <ul>{product.details.map(d => <li key={d}>{d}</li>)}</ul> },
              { title: 'Care', body: <p>{product.care}</p> },
              {
                title: 'Shipping & returns',
                body: (
                  <p>
                    Standard shipping is free over {money(settings.freeShippingOver)}, otherwise{' '}
                    {money(settings.standardShipping)}. Returns are free within {settings.returnsWindow} days
                    on unworn pieces with tags attached.
                  </p>
                ),
              },
            ]}
          />
        </div>
      </div>

      {related.length > 0 && (
        <section className="section" style={{ paddingTop: 0 }}>
          <div className="section__head">
            <div>
              <h2>Wears well with</h2>
              <p>Pulled from the same category and shared material tags.</p>
            </div>
          </div>
          <div className="grid grid--tight">
            {related.map(item => (
              <ProductCard
                key={item.id} product={item} wished={false}
                onWish={onWish} onOpen={onOpenProduct}
                onQuickAdd={(p, s, c) => onAdd(p, s, c, 1)}
              />
            ))}
          </div>
        </section>
      )}

      <SizeGuide open={guide} sizeType={product.sizeType} onClose={() => setGuide(false)} />
    </div>
  )
}
