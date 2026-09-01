import { useState } from 'react'
import { Overview, ProductsAdmin, OrdersAdmin, InventoryAdmin, CustomersAdmin, StudioAdmin, SettingsAdmin } from './screens.jsx'
import { useShop, useAdminMetrics } from '../store/ShopContext.jsx'
import { usePersistentState } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

const DEMO_EMAIL = 'admin@rareform.studio'
const DEMO_PASSWORD = 'admin123'

const SECTIONS = [
  { id: 'overview', label: 'Overview', icon: 'grid' },
  { id: 'products', label: 'Products', icon: 'cube' },
  { id: 'orders', label: 'Orders', icon: 'truck' },
  { id: 'inventory', label: 'Inventory', icon: 'layers' },
  { id: 'customers', label: 'Customers', icon: 'user' },
  { id: 'studio', label: '3D Studio', icon: 'sparkle' },
  { id: 'settings', label: 'Settings', icon: 'sliders' },
]

function Login({ onAuth }) {
  const [email, setEmail] = useState(DEMO_EMAIL)
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)

  const submit = event => {
    event.preventDefault()
    if (email.trim().toLowerCase() === DEMO_EMAIL && password === DEMO_PASSWORD) {
      onAuth()
      return
    }
    setError('Those credentials do not match the demo account.')
  }

  return (
    <div className="login">
      <form className="login__card" onSubmit={submit}>
        <div className="admin__brand" style={{ padding: 0, marginBottom: 18 }}>
          RARE<span>·</span>FORM <em>Admin</em>
        </div>
        <h1>Control panel</h1>
        <p className="muted" style={{ fontSize: 13.5, marginTop: 8, marginBottom: 20 }}>
          Manage the catalogue, orders, stock and the 3D render pipeline.
        </p>

        <div className="checkout">
          <div className="field">
            <label htmlFor="ad-email">Email</label>
            <input id="ad-email" type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="username" />
          </div>
          <div className="field">
            <label htmlFor="ad-pass">Password</label>
            <input id="ad-pass" type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete="current-password" />
          </div>
          {error && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13 }}>{error}</p>}
          <button type="submit" className="btn btn--primary btn--block">Sign in</button>
        </div>

        <div className="login__demo">
          Demo account<br />
          {DEMO_EMAIL}<br />
          {DEMO_PASSWORD}
        </div>
        <p className="field__hint" style={{ marginTop: 14 }}>
          This check runs in the browser and guards nothing. A real store needs server-side
          authentication before it goes anywhere near production.
        </p>
      </form>
    </div>
  )
}

export default function AdminApp({ onExit, notify }) {
  const [authed, setAuthed] = usePersistentState('rf.admin.session', false)
  const [section, setSection] = useState('overview')
  const { products, orders, settings } = useShop()
  const metrics = useAdminMetrics()

  if (!authed) return <Login onAuth={() => setAuthed(true)} />

  const counts = {
    products: products.length,
    orders: metrics.openOrders,
    inventory: metrics.lowStock.length,
    customers: metrics.customerCount,
  }

  const current = SECTIONS.find(s => s.id === section)

  return (
    <div className="admin">
      <nav className="admin__rail" aria-label="Admin sections">
        <div className="admin__brand">RARE<span>·</span>FORM <em>Admin</em></div>
        <div className="admin__nav">
          {SECTIONS.map(item => (
            <button
              key={item.id} type="button" onClick={() => setSection(item.id)}
              aria-current={section === item.id ? 'page' : undefined}
            >
              <Icon name={item.icon} size={15} />
              {item.label}
              {counts[item.id] !== undefined && <em>{counts[item.id]}</em>}
            </button>
          ))}
        </div>
        <div className="admin__railfoot">
          <button type="button" className="btn btn--ghost btn--sm" onClick={onExit}>
            <Icon name="arrowLeft" size={13} /> View storefront
          </button>
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => setAuthed(false)}>
            <Icon name="lock" size={13} /> Sign out
          </button>
        </div>
      </nav>

      <div className="admin__main">
        <header className="admin__top">
          <div>
            <h1>{current.label}</h1>
            <p>
              {section === 'overview' && `${settings.storeName} · ${orders.length} orders on record`}
              {section === 'products' && 'Every field here feeds the 3D model and the storefront'}
              {section === 'orders' && `${metrics.openOrders} awaiting fulfilment`}
              {section === 'inventory' && `Threshold set at ${settings.lowStockThreshold} units`}
              {section === 'customers' && 'Ranked by lifetime spend'}
              {section === 'studio' && 'Lighting and render options for the whole shop'}
              {section === 'settings' && 'Store, shipping and promo configuration'}
            </p>
          </div>
        </header>

        <div className="admin__body">
          {section === 'overview' && <Overview onNavigate={setSection} />}
          {section === 'products' && <ProductsAdmin />}
          {section === 'orders' && <OrdersAdmin />}
          {section === 'inventory' && <InventoryAdmin />}
          {section === 'customers' && <CustomersAdmin />}
          {section === 'studio' && <StudioAdmin notify={notify} />}
          {section === 'settings' && <SettingsAdmin notify={notify} />}
        </div>
      </div>
    </div>
  )
}
