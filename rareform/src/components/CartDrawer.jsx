import { useRef, useState } from 'react'
import { GarmentImage } from './ProductCard.jsx'
import { useFocusTrap, useLockBody, money } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

const FREE_SHIPPING = 150

export default function CartDrawer({ open, lines, onClose, onQty, onRemove, onCheckout }) {
  const panelRef = useRef(null)
  const [promo, setPromo] = useState('')
  const [applied, setApplied] = useState(null)
  useLockBody(open)
  useFocusTrap(open, panelRef)

  if (!open) return null

  const subtotal = lines.reduce((sum, line) => sum + line.product.price * line.qty, 0)
  const discount = applied ? Math.round(subtotal * applied.rate) : 0
  const shipping = subtotal === 0 || subtotal - discount >= FREE_SHIPPING ? 0 : 8
  const total = subtotal - discount + shipping
  const remaining = Math.max(0, FREE_SHIPPING - (subtotal - discount))

  const applyPromo = event => {
    event.preventDefault()
    const code = promo.trim().toUpperCase()
    if (code === 'FORM10') setApplied({ code, rate: 0.1 })
    else if (code === 'STUDIO20') setApplied({ code, rate: 0.2 })
    else setApplied({ code, rate: 0, invalid: true })
  }

  return (
    <>
      <div className="scrim" onClick={onClose} />
      <aside className="drawer" ref={panelRef} role="dialog" aria-modal="true" aria-label="Shopping bag">
        <header className="drawer__head">
          <h2>Bag <span className="mono muted">({lines.reduce((n, l) => n + l.qty, 0)})</span></h2>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close bag"><Icon name="x" /></button>
        </header>

        <div className="drawer__body">
          {lines.length === 0
            ? (
              <div style={{ textAlign: 'center', padding: '60px 10px' }}>
                <Icon name="bag" size={30} />
                <h3 style={{ marginTop: 14, fontSize: 17, textTransform: 'uppercase' }}>Your bag is empty</h3>
                <p className="muted" style={{ marginTop: 8, fontSize: 13.5 }}>Every piece is rendered live — go find one.</p>
                <button type="button" className="btn btn--primary" style={{ marginTop: 18 }} onClick={onClose}>Continue shopping</button>
              </div>
            )
            : (
              <>
                {subtotal > 0 && (
                  <div style={{ marginBottom: 16 }}>
                    <p className="mono muted" style={{ marginBottom: 7 }}>
                      {remaining > 0 ? `${money(remaining)} to free shipping` : 'Free shipping unlocked'}
                    </p>
                    <div className="progress"><i style={{ width: `${Math.min(100, ((subtotal - discount) / FREE_SHIPPING) * 100)}%` }} /></div>
                  </div>
                )}
                {lines.map(line => (
                  <div className="line" key={line.key}>
                    <div className="line__img">
                      <GarmentImage product={line.product} colorway={line.colorway} className="card__img" />
                    </div>
                    <div>
                      <div className="line__top">
                        <span className="line__name">{line.product.name}</span>
                        <span className="mono">{money(line.product.price * line.qty)}</span>
                      </div>
                      <div className="line__meta">{line.colorway.name} · Size {line.size}</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div className="qty">
                          <button type="button" onClick={() => onQty(line.key, -1)} aria-label={`Decrease quantity of ${line.product.name}`}>
                            <Icon name="minus" size={13} />
                          </button>
                          <span>{line.qty}</span>
                          <button type="button" onClick={() => onQty(line.key, 1)} aria-label={`Increase quantity of ${line.product.name}`}>
                            <Icon name="plus" size={13} />
                          </button>
                        </div>
                        <button
                          type="button" className="btn btn--ghost btn--sm" style={{ marginTop: 10 }}
                          onClick={() => onRemove(line.key)}
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  </div>
                ))}

                <form onSubmit={applyPromo} style={{ display: 'flex', gap: 8, marginTop: 18 }}>
                  <div className="field" style={{ flex: 1 }}>
                    <label htmlFor="promo">Promo code</label>
                    <input id="promo" value={promo} onChange={e => setPromo(e.target.value)} placeholder="FORM10" />
                  </div>
                  <button type="submit" className="btn" style={{ alignSelf: 'flex-end' }}>Apply</button>
                </form>
                {applied && (
                  <p style={{ marginTop: 8, fontSize: 12.5, color: applied.invalid ? 'var(--danger)' : 'var(--positive)' }}>
                    {applied.invalid ? `“${applied.code}” is not a valid code.` : `${applied.code} applied — ${applied.rate * 100}% off.`}
                  </p>
                )}
              </>
            )}
        </div>

        {lines.length > 0 && (
          <footer className="drawer__foot">
            <div className="totals">
              <div><span>Subtotal</span><span>{money(subtotal)}</span></div>
              {discount > 0 && <div style={{ color: 'var(--positive)' }}><span>Discount</span><span>−{money(discount)}</span></div>}
              <div><span>Shipping</span><span>{shipping === 0 ? 'Free' : money(shipping)}</span></div>
              <div className="grand"><span>Total</span><span>{money(total)}</span></div>
            </div>
            <button type="button" className="btn btn--signal btn--block" onClick={() => onCheckout(total)}>
              Checkout <Icon name="arrowRight" size={15} />
            </button>
            <p className="mono muted" style={{ textAlign: 'center', fontSize: 9.5 }}>
              <Icon name="lock" size={10} /> Demo checkout — no payment is taken
            </p>
          </footer>
        )}
      </aside>
    </>
  )
}
