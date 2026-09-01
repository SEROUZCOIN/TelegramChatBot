import { useMemo, useState } from 'react'
import Viewer3D from '../components/Viewer3D.jsx'
import { GarmentImage } from '../components/ProductCard.jsx'
import ProductEditor from './ProductEditor.jsx'
import { CATEGORIES, garmentSpec } from '../data/catalog.js'
import { ORDER_STATES } from '../data/commerce.js'
import { SCENE_PRESETS } from '../three/studio.js'
import { clearThumbnailCaches } from '../three/thumbnails.js'
import { useShop, useAdminMetrics } from '../store/ShopContext.jsx'
import { money } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

/* ------------------------------------------------------------------ Overview */

export function Overview({ onNavigate }) {
  const metrics = useAdminMetrics()
  const peak = Math.max(1, ...metrics.series.map(point => point.value))

  return (
    <>
      <dl className="kpis">
        <div className="kpi">
          <dt>Revenue · 28 days</dt>
          <dd>{money(metrics.revenue)}</dd>
          <span className="kpi__delta" data-dir={metrics.trend >= 0 ? 'up' : 'down'}>
            <Icon name={metrics.trend >= 0 ? 'chevronUp' : 'chevronDown'} size={11} strokeWidth={2.4} />
            {metrics.trend >= 0 ? '+' : ''}{metrics.trend.toFixed(1)}% week on week
          </span>
        </div>
        <div className="kpi">
          <dt>Orders</dt>
          <dd>{metrics.orderCount}</dd>
          <span className="kpi__delta">{metrics.openOrders} awaiting fulfilment</span>
        </div>
        <div className="kpi">
          <dt>Average order</dt>
          <dd>{money(metrics.aov)}</dd>
          <span className="kpi__delta">{metrics.units} units sold</span>
        </div>
        <div className="kpi">
          <dt>Refunded</dt>
          <dd>{money(metrics.refunded)}</dd>
          <span className="kpi__delta">{metrics.customerCount} customers</span>
        </div>
      </dl>

      <div className="cols">
        <section className="panel">
          <header className="panel__head">
            <h2>Revenue by day</h2>
            <div className="spacer" />
            <span className="mono muted">Last 28 days · peak {money(peak)}</span>
          </header>
          <div className="panel__body">
            <div className="bars">
              {metrics.series.map(point => (
                <div key={point.daysAgo} data-recent={point.daysAgo < 7} title={`${point.daysAgo}d ago — ${money(point.value)}`}>
                  <i style={{ height: `${Math.max(2, (point.value / peak) * 100)}%` }} />
                </div>
              ))}
            </div>
            <div className="bars__axis">
              <span>28 days ago</span>
              <span>14</span>
              <span>7</span>
              <span>Today</span>
            </div>
          </div>
        </section>

        <section className="panel">
          <header className="panel__head">
            <h2>Low stock</h2>
            <div className="spacer" />
            <button type="button" className="btn btn--ghost btn--sm" onClick={() => onNavigate('inventory')}>Manage</button>
          </header>
          <div className="panel__body" style={{ display: 'grid', gap: 12 }}>
            {metrics.lowStock.length === 0 && <p className="muted" style={{ fontSize: 13 }}>Everything is above the threshold.</p>}
            {metrics.lowStock.slice(0, 6).map(product => (
              <div key={product.id} className="rowline">
                <span className="thumb"><GarmentImage product={product} colorway={product.colorways[0]} /></span>
                <span style={{ minWidth: 0, flex: 1 }}>
                  <strong>{product.name}</strong>
                  <span>{product.categoryLabel}</span>
                </span>
                <span className="mono" style={{ color: product.stock === 0 ? 'var(--danger)' : 'var(--text-2)' }}>
                  {product.stock}
                </span>
              </div>
            ))}
          </div>
        </section>
      </div>

      <section className="panel">
        <header className="panel__head">
          <h2>Top garments by revenue</h2>
          <div className="spacer" />
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => onNavigate('products')}>All products</button>
        </header>
        <div className="panel__body panel__body--flush">
          <div className="tablewrap">
            <table className="data">
              <thead>
                <tr>
                  <th scope="col">Garment</th>
                  <th scope="col">Category</th>
                  <th scope="col" className="num">Units</th>
                  <th scope="col" className="num">Revenue</th>
                  <th scope="col" className="num">Stock</th>
                </tr>
              </thead>
              <tbody>
                {metrics.top.map(row => (
                  <tr key={row.product.id}>
                    <td>
                      <div className="rowline">
                        <span className="thumb"><GarmentImage product={row.product} colorway={row.product.colorways[0]} /></span>
                        <span><strong>{row.product.name}</strong><span>{row.product.sku}</span></span>
                      </div>
                    </td>
                    <td>{row.product.categoryLabel}</td>
                    <td className="num">{row.units}</td>
                    <td className="num">{money(row.revenue)}</td>
                    <td className="num">{row.product.stock}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </>
  )
}

/* ------------------------------------------------------------------ Products */

export function ProductsAdmin() {
  const { products } = useShop()
  const [editing, setEditing] = useState(null)
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')

  const rows = useMemo(() => products.filter(product => {
    if (category !== 'all' && product.category !== category) return false
    if (!query.trim()) return true
    const needle = query.toLowerCase()
    return product.name.toLowerCase().includes(needle) || product.sku.toLowerCase().includes(needle)
  }), [products, query, category])

  if (editing !== null) {
    return (
      <section className="panel">
        <header className="panel__head">
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => setEditing(null)}>
            <Icon name="arrowLeft" size={14} /> Back
          </button>
          <h2>{editing === 'new' ? 'New garment' : 'Edit garment'}</h2>
        </header>
        <div className="panel__body">
          <ProductEditor productId={editing === 'new' ? null : editing} onDone={() => setEditing(null)} />
        </div>
      </section>
    )
  }

  return (
    <section className="panel">
      <header className="panel__head">
        <h2>Catalogue</h2>
        <span className="mono muted">{rows.length} of {products.length}</span>
        <div className="spacer" />
        <input
          value={query} onChange={e => setQuery(e.target.value)} placeholder="Search name or SKU"
          aria-label="Search products"
          style={{ height: 36, padding: '0 12px', border: '1px solid var(--line)', borderRadius: 4, background: 'var(--surface)' }}
        />
        <select className="select" value={category} onChange={e => setCategory(e.target.value)} aria-label="Filter by category">
          <option value="all">All categories</option>
          {CATEGORIES.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
        </select>
        <button type="button" className="btn btn--primary btn--sm" onClick={() => setEditing('new')}>
          <Icon name="plus" size={14} /> New garment
        </button>
      </header>

      <div className="panel__body panel__body--flush">
        <div className="tablewrap">
          <table className="data">
            <thead>
              <tr>
                <th scope="col">Garment</th>
                <th scope="col">Category</th>
                <th scope="col">Model</th>
                <th scope="col">Colours</th>
                <th scope="col" className="num">Price</th>
                <th scope="col" className="num">Stock</th>
                <th scope="col" />
              </tr>
            </thead>
            <tbody>
              {rows.map(product => (
                <tr key={product.id}>
                  <td>
                    <div className="rowline">
                      <span className="thumb"><GarmentImage product={product} colorway={product.colorways[0]} /></span>
                      <span><strong>{product.name}</strong><span>{product.sku}</span></span>
                    </div>
                  </td>
                  <td>{product.categoryLabel}</td>
                  <td><span className="tag">{product.kind} · {product.fit}</span></td>
                  <td>
                    <span style={{ display: 'inline-flex', gap: 4 }}>
                      {product.colorways.map(cw => (
                        <span
                          key={cw.name} title={cw.name}
                          style={{ width: 14, height: 14, borderRadius: '50%', background: cw.hex, border: '1px solid var(--line-strong)' }}
                        />
                      ))}
                    </span>
                  </td>
                  <td className="num">{money(product.price)}</td>
                  <td className="num">{product.stock}</td>
                  <td className="num">
                    <button type="button" className="btn btn--ghost btn--sm" onClick={() => setEditing(product.id)}>Edit</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

/* ------------------------------------------------------------------ Orders */

export function OrdersAdmin() {
  const { orders, setOrderStatus } = useShop()
  const [filter, setFilter] = useState('all')
  const [open, setOpen] = useState(null)

  const rows = filter === 'all' ? orders : orders.filter(order => order.status === filter)

  return (
    <section className="panel">
      <header className="panel__head">
        <h2>Orders</h2>
        <span className="mono muted">{rows.length} shown</span>
        <div className="spacer" />
        <select className="select" value={filter} onChange={e => setFilter(e.target.value)} aria-label="Filter orders by status">
          <option value="all">All statuses</option>
          {ORDER_STATES.map(state => <option key={state} value={state}>{state}</option>)}
        </select>
      </header>
      <div className="panel__body panel__body--flush">
        <div className="tablewrap">
          <table className="data">
            <thead>
              <tr>
                <th scope="col">Order</th>
                <th scope="col">Customer</th>
                <th scope="col">Placed</th>
                <th scope="col" className="num">Items</th>
                <th scope="col" className="num">Total</th>
                <th scope="col">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(order => (
                <>
                  <tr key={order.id}>
                    <td>
                      <button
                        type="button" onClick={() => setOpen(open === order.id ? null : order.id)}
                        style={{ background: 'none', border: 0, cursor: 'pointer', fontFamily: 'var(--font-mono)', fontSize: 12, display: 'inline-flex', alignItems: 'center', gap: 6 }}
                        aria-expanded={open === order.id}
                      >
                        <Icon name={open === order.id ? 'chevronUp' : 'chevronDown'} size={12} />
                        {order.id}
                      </button>
                    </td>
                    <td>{order.customer}<br /><span className="mono muted" style={{ fontSize: 10 }}>{order.city}</span></td>
                    <td className="mono">{order.placedAt}</td>
                    <td className="num">{order.items.reduce((n, item) => n + item.qty, 0)}</td>
                    <td className="num">{money(order.total)}</td>
                    <td>
                      <select
                        className="select" value={order.status} aria-label={`Status for order ${order.id}`}
                        onChange={e => setOrderStatus(order.id, e.target.value)}
                        style={{ height: 32, fontSize: 12 }}
                      >
                        {ORDER_STATES.map(state => <option key={state} value={state}>{state}</option>)}
                      </select>
                    </td>
                  </tr>
                  {open === order.id && (
                    <tr key={`${order.id}-detail`}>
                      <td colSpan={6} style={{ background: 'var(--surface-2)' }}>
                        <div style={{ display: 'grid', gap: 8, padding: '4px 0' }}>
                          {order.items.map((item, index) => (
                            <div key={index} className="rowline" style={{ fontSize: 13 }}>
                              <span className="status" data-state={order.status}>{order.status}</span>
                              <span style={{ flex: 1 }}>{item.qty} × {item.name} — {item.colorName}, size {item.size}</span>
                              <span className="mono">{money(item.price * item.qty)}</span>
                            </div>
                          ))}
                          <span className="mono muted">{order.email}</span>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

/* ------------------------------------------------------------------ Inventory */

export function InventoryAdmin() {
  const { products, adjustStock, settings } = useShop()
  const [lowOnly, setLowOnly] = useState(false)
  const rows = lowOnly ? products.filter(p => p.stock <= settings.lowStockThreshold) : products
  const ceiling = Math.max(1, ...products.map(p => p.stock))

  return (
    <section className="panel">
      <header className="panel__head">
        <h2>Inventory</h2>
        <span className="mono muted">{rows.length} lines</span>
        <div className="spacer" />
        <label className="toggle">
          <input type="checkbox" checked={lowOnly} onChange={e => setLowOnly(e.target.checked)} />
          <span className="toggle__track" />
          <span>Low stock only</span>
        </label>
      </header>
      <div className="panel__body panel__body--flush">
        <div className="tablewrap">
          <table className="data">
            <thead>
              <tr>
                <th scope="col">Garment</th>
                <th scope="col">Level</th>
                <th scope="col" className="num">On hand</th>
                <th scope="col" className="num">Adjust</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(product => {
                const low = product.stock <= settings.lowStockThreshold
                return (
                  <tr key={product.id}>
                    <td>
                      <div className="rowline">
                        <span className="thumb"><GarmentImage product={product} colorway={product.colorways[0]} /></span>
                        <span><strong>{product.name}</strong><span>{product.sku}</span></span>
                      </div>
                    </td>
                    <td>
                      <span className="stockbar" data-low={low}>
                        <span className="stockbar__track"><i style={{ width: `${(product.stock / ceiling) * 100}%` }} /></span>
                        {low && <span className="tag" style={{ color: 'var(--danger)' }}>Low</span>}
                      </span>
                    </td>
                    <td className="num">{product.stock}</td>
                    <td className="num">
                      <span style={{ display: 'inline-flex', gap: 4 }}>
                        <button type="button" className="btn btn--sm" onClick={() => adjustStock(product.id, -1)} aria-label={`Remove one ${product.name}`}>−1</button>
                        <button type="button" className="btn btn--sm" onClick={() => adjustStock(product.id, 1)} aria-label={`Add one ${product.name}`}>+1</button>
                        <button type="button" className="btn btn--sm" onClick={() => adjustStock(product.id, 25)} aria-label={`Add 25 ${product.name}`}>+25</button>
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

/* ------------------------------------------------------------------ Customers */

export function CustomersAdmin() {
  const { customers, orders } = useShop()
  const rows = useMemo(() => customers.map(customer => {
    const theirs = orders.filter(order => order.customerId === customer.id && order.status !== 'Refunded')
    return {
      ...customer,
      orders: theirs.length,
      spend: theirs.reduce((sum, order) => sum + order.total, 0),
      last: theirs[0]?.placedAt ?? '—',
    }
  }).sort((a, b) => b.spend - a.spend), [customers, orders])

  return (
    <section className="panel">
      <header className="panel__head">
        <h2>Customers</h2>
        <span className="mono muted">{rows.length} people</span>
      </header>
      <div className="panel__body panel__body--flush">
        <div className="tablewrap">
          <table className="data">
            <thead>
              <tr>
                <th scope="col">Name</th>
                <th scope="col">Email</th>
                <th scope="col">City</th>
                <th scope="col" className="num">Orders</th>
                <th scope="col" className="num">Lifetime spend</th>
                <th scope="col">Last order</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(row => (
                <tr key={row.id}>
                  <td><strong style={{ fontWeight: 500 }}>{row.name}</strong></td>
                  <td className="mono" style={{ fontSize: 11.5 }}>{row.email}</td>
                  <td>{row.city}</td>
                  <td className="num">{row.orders}</td>
                  <td className="num">{money(row.spend)}</td>
                  <td className="mono">{row.last}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

/* ------------------------------------------------------------------ Studio */

export function StudioAdmin({ notify }) {
  const { studio, setStudio, products } = useShop()
  const hero = products[0]
  const set = (key, value) => setStudio(current => ({ ...current, [key]: value }))

  return (
    <div className="cols">
      <div style={{ display: 'grid', gap: 20 }}>
        <section className="panel">
          <header className="panel__head"><h2>Product page scene</h2></header>
          <div className="panel__body">
            <div className="presetgrid">
              {Object.entries(SCENE_PRESETS).map(([id, preset]) => (
                <button key={id} type="button" aria-pressed={studio.preset === id} onClick={() => set('preset', id)}>
                  <i style={{ background: `linear-gradient(150deg, ${preset.backdrop[0]}, ${preset.backdrop[1]})`, border: '1px solid var(--line)' }} />
                  {preset.label}
                </button>
              ))}
            </div>
          </div>
        </section>

        <section className="panel">
          <header className="panel__head">
            <h2>Catalogue card scene</h2>
            <div className="spacer" />
            <span className="mono muted">Redraws every card</span>
          </header>
          <div className="panel__body">
            <div className="presetgrid">
              {Object.entries(SCENE_PRESETS).map(([id, preset]) => (
                <button key={id} type="button" aria-pressed={studio.cardPreset === id} onClick={() => set('cardPreset', id)}>
                  <i style={{ background: `linear-gradient(150deg, ${preset.backdrop[0]}, ${preset.backdrop[1]})`, border: '1px solid var(--line)' }} />
                  {preset.label}
                </button>
              ))}
            </div>
          </div>
        </section>

        <section className="panel">
          <header className="panel__head"><h2>Render settings</h2></header>
          <div className="panel__body" style={{ display: 'grid', gap: 16 }}>
            <div className="slider">
              <label htmlFor="st-angle" className="mono muted">Presentation angle</label>
              <div className="slider__row">
                <input
                  id="st-angle" type="range" min="-1.6" max="1.6" step="0.02" value={studio.angle}
                  onChange={e => set('angle', Number(e.target.value))}
                />
                <output>{(studio.angle * (180 / Math.PI)).toFixed(0)}°</output>
              </div>
            </div>

            <div className="slider">
              <label htmlFor="st-exposure" className="mono muted">Exposure</label>
              <div className="slider__row">
                <input
                  id="st-exposure" type="range" min="0.5" max="1.8" step="0.02" value={studio.exposure}
                  onChange={e => set('exposure', Number(e.target.value))}
                />
                <output>{studio.exposure.toFixed(2)}</output>
              </div>
            </div>

            <div className="slider">
              <label htmlFor="st-bloom" className="mono muted">Bloom strength</label>
              <div className="slider__row">
                <input
                  id="st-bloom" type="range" min="0" max="1.4" step="0.02" value={studio.bloomStrength}
                  disabled={!studio.bloom}
                  onChange={e => set('bloomStrength', Number(e.target.value))}
                />
                <output>{studio.bloomStrength.toFixed(2)}</output>
              </div>
            </div>

            <label className="toggle">
              <input type="checkbox" checked={studio.bloom} onChange={e => set('bloom', e.target.checked)} />
              <span className="toggle__track" />
              <span>Bloom post-processing</span>
            </label>
            <label className="toggle">
              <input type="checkbox" checked={studio.grid} onChange={e => set('grid', e.target.checked)} />
              <span className="toggle__track" />
              <span>Grid floor</span>
            </label>
            <label className="toggle">
              <input type="checkbox" checked={studio.autoRotate} onChange={e => set('autoRotate', e.target.checked)} />
              <span className="toggle__track" />
              <span>Auto-rotate on product pages</span>
            </label>

            <button
              type="button" className="btn"
              onClick={() => { clearThumbnailCaches(); notify('Card renders cleared — they will redraw as you browse.') }}
            >
              <Icon name="refresh" size={14} /> Re-render all catalogue cards
            </button>
          </div>
        </section>
      </div>

      <section className="panel">
        <header className="panel__head">
          <h2>Live preview</h2>
          <div className="spacer" />
          <span className="mono muted">{hero?.name}</span>
        </header>
        <div className="panel__body">
          <div style={{ aspectRatio: '4 / 5', borderRadius: 8, overflow: 'hidden', border: '1px solid var(--line)' }}>
            {hero && (
              <Viewer3D
                spec={garmentSpec(hero, hero.colorways[0], studio.angle)}
                label={hero.name} preset={studio.preset} bloom={studio.bloom}
                bloomStrength={studio.bloomStrength} grid={studio.grid} exposure={studio.exposure}
                autoRotate={studio.autoRotate} showHud={false} showTelemetry
              />
            )}
          </div>
          <p className="field__hint" style={{ marginTop: 12 }}>
            These settings drive the storefront viewer and every catalogue card. Changing the
            card scene clears the render cache so cards redraw at the new lighting.
          </p>
        </div>
      </section>
    </div>
  )
}

/* ------------------------------------------------------------------ Settings */

export function SettingsAdmin({ notify }) {
  const { settings, setSettings, resetDemo } = useShop()
  const set = (key, value) => setSettings(current => ({ ...current, [key]: value }))

  const setPromo = (index, patch) => setSettings(current => ({
    ...current,
    promos: current.promos.map((promo, i) => (i === index ? { ...promo, ...patch } : promo)),
  }))

  return (
    <div className="cols cols--even">
      <section className="panel">
        <header className="panel__head"><h2>Store</h2></header>
        <div className="panel__body editor__grid">
          <div className="field field--wide">
            <label htmlFor="se-name">Store name</label>
            <input id="se-name" value={settings.storeName} onChange={e => set('storeName', e.target.value)} />
          </div>
          <div className="field">
            <label htmlFor="se-currency">Currency</label>
            <select id="se-currency" value={settings.currency} onChange={e => set('currency', e.target.value)}>
              <option value="GBP">GBP £</option>
              <option value="USD">USD $</option>
              <option value="EUR">EUR €</option>
              <option value="JPY">JPY ¥</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="se-ship">Free shipping over</label>
            <input id="se-ship" type="number" min="0" value={settings.freeShippingOver} onChange={e => set('freeShippingOver', Number(e.target.value))} />
          </div>
          <div className="field">
            <label htmlFor="se-flat">Standard shipping</label>
            <input id="se-flat" type="number" min="0" value={settings.standardShipping} onChange={e => set('standardShipping', Number(e.target.value))} />
          </div>
          <div className="field">
            <label htmlFor="se-low">Low stock threshold</label>
            <input id="se-low" type="number" min="0" value={settings.lowStockThreshold} onChange={e => set('lowStockThreshold', Number(e.target.value))} />
          </div>
          <div className="field">
            <label htmlFor="se-returns">Returns window (days)</label>
            <input id="se-returns" type="number" min="0" value={settings.returnsWindow} onChange={e => set('returnsWindow', Number(e.target.value))} />
          </div>
        </div>
      </section>

      <section className="panel">
        <header className="panel__head">
          <h2>Promo codes</h2>
          <div className="spacer" />
          <button
            type="button" className="btn btn--ghost btn--sm"
            onClick={() => setSettings(c => ({ ...c, promos: [...c.promos, { code: 'NEWCODE', rate: 0.1, active: true }] }))}
          >
            <Icon name="plus" size={13} /> Add
          </button>
        </header>
        <div className="panel__body" style={{ display: 'grid', gap: 12 }}>
          {settings.promos.map((promo, index) => (
            <div key={index} style={{ display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
              <div className="field" style={{ flex: 1, minWidth: 120 }}>
                <label htmlFor={`promo-code-${index}`}>Code</label>
                <input
                  id={`promo-code-${index}`} value={promo.code}
                  onChange={e => setPromo(index, { code: e.target.value.toUpperCase() })}
                />
              </div>
              <div className="field" style={{ width: 100 }}>
                <label htmlFor={`promo-rate-${index}`}>Discount %</label>
                <input
                  id={`promo-rate-${index}`} type="number" min="0" max="90"
                  value={Math.round(promo.rate * 100)}
                  onChange={e => setPromo(index, { rate: Number(e.target.value) / 100 })}
                />
              </div>
              <label className="toggle">
                <input type="checkbox" checked={promo.active} onChange={e => setPromo(index, { active: e.target.checked })} />
                <span className="toggle__track" />
                <span>Active</span>
              </label>
              <button
                type="button" className="btn btn--sm"
                onClick={() => setSettings(c => ({ ...c, promos: c.promos.filter((_, i) => i !== index) }))}
              >
                Remove
              </button>
            </div>
          ))}
          <p className="field__hint">Codes apply in the storefront bag immediately.</p>
        </div>
      </section>

      <section className="panel">
        <header className="panel__head"><h2>Demo data</h2></header>
        <div className="panel__body" style={{ display: 'grid', gap: 12 }}>
          <p className="muted" style={{ fontSize: 13.5, lineHeight: 1.6 }}>
            Products, orders, settings and render options all live in this browser. Resetting
            restores the seeded catalogue and clears anything you have changed here.
          </p>
          <button
            type="button" className="btn"
            onClick={() => { resetDemo(); clearThumbnailCaches(); notify('Demo data reset to the seeded catalogue.') }}
          >
            <Icon name="reset" size={14} /> Reset everything
          </button>
        </div>
      </section>
    </div>
  )
}
