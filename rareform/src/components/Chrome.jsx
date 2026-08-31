import { useEffect, useRef, useState } from 'react'
import Viewer3D from './Viewer3D.jsx'
import { CATEGORIES, CATEGORY_GROUPS, COLLECTIONS, DEPARTMENTS, PRODUCTS } from '../data/catalog.js'
import { garmentSpec } from '../data/catalog.js'
import { Icon } from '../lib/icons.jsx'

export function Header({
  cartCount, wishCount, theme, onTheme, onSearch, onHome, onCategory, onCollection,
  onDepartment, onCart, onWishlist, activeView,
}) {
  const [menu, setMenu] = useState(null)
  const [mobileNav, setMobileNav] = useState(false)
  const holdRef = useRef(null)

  const openMenu = key => {
    clearTimeout(holdRef.current)
    setMenu(key)
  }
  const closeMenu = () => {
    holdRef.current = setTimeout(() => setMenu(null), 140)
  }
  useEffect(() => () => clearTimeout(holdRef.current), [])

  return (
    <header className="header" onMouseLeave={closeMenu}>
      <div className="shell header__bar">
        <button type="button" className="header__logo" onClick={onHome}>
          RARE<span>·</span>FORM
        </button>

        <nav className="header__nav" aria-label="Primary">
          {DEPARTMENTS.map(dep => (
            <button
              key={dep} type="button"
              onMouseEnter={() => openMenu(dep)} onFocus={() => openMenu(dep)}
              onClick={() => { onDepartment(dep); setMenu(null) }}
              data-active={menu === dep}
              aria-expanded={menu === dep}
            >
              {dep}
            </button>
          ))}
          <button type="button" onMouseEnter={() => openMenu('collections')} onFocus={() => openMenu('collections')} data-active={menu === 'collections'}>
            Collections
          </button>
        </nav>

        <div className="header__spacer" />

        <button type="button" className="searchbtn" onClick={onSearch}>
          <Icon name="search" size={16} />
          <span className="searchbtn__label">Search garments…</span>
          <kbd>⌘K</kbd>
        </button>

        <button type="button" className="icon-btn" onClick={onTheme} aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}>
          <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={17} />
        </button>

        <button type="button" className="icon-btn" onClick={onWishlist} aria-label={`Wishlist, ${wishCount} saved`} aria-pressed={activeView === 'wishlist'}>
          <Icon name="heart" size={17} />
          {wishCount > 0 && <span className="badge-count">{wishCount}</span>}
        </button>

        <button type="button" className="icon-btn" onClick={onCart} aria-label={`Bag, ${cartCount} items`}>
          <Icon name="bag" size={17} />
          {cartCount > 0 && <span className="badge-count">{cartCount}</span>}
        </button>

        <button type="button" className="icon-btn mobile-only" onClick={() => setMobileNav(v => !v)} aria-label="Menu" aria-expanded={mobileNav}>
          <Icon name={mobileNav ? 'x' : 'menu'} size={19} />
        </button>
      </div>

      {menu && (
        <div className="megamenu" onMouseEnter={() => openMenu(menu)} onMouseLeave={closeMenu}>
          <div className="shell megamenu__grid">
            {menu === 'collections'
              ? (
                <>
                  <div>
                    <h4>Collections</h4>
                    <ul>
                      {COLLECTIONS.map(col => (
                        <li key={col.id}>
                          <button type="button" onClick={() => { onCollection(col.id); setMenu(null) }}>
                            {col.label}
                            <em>{PRODUCTS.filter(col.test).length}</em>
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>
                  <div style={{ gridColumn: 'span 2' }}>
                    <h4>Rendered, not photographed</h4>
                    <p className="muted" style={{ fontSize: 13.5, maxWidth: '48ch', lineHeight: 1.65 }}>
                      Every garment on RAREFORM is generated as real 3D geometry and lit in a virtual studio
                      in your browser. No sample shoots, no stock photos — spin any piece to see how it actually falls.
                    </p>
                  </div>
                </>
              )
              : CATEGORY_GROUPS.map(group => (
                <div key={group}>
                  <h4>{group}</h4>
                  <ul>
                    {CATEGORIES.filter(cat => cat.group === group).map(cat => {
                      const count = PRODUCTS.filter(p => p.category === cat.id && (menu === 'Unisex' || p.department === menu || p.department === 'Unisex')).length
                      return (
                        <li key={cat.id}>
                          <button type="button" onClick={() => { onCategory(cat.id, menu); setMenu(null) }}>
                            {cat.label}
                            <em>{count}</em>
                          </button>
                        </li>
                      )
                    })}
                  </ul>
                </div>
              ))}
          </div>
        </div>
      )}

      {mobileNav && (
        <div className="megamenu mobile-only">
          <div className="shell megamenu__grid">
            <div>
              <h4>Departments</h4>
              <ul>
                {DEPARTMENTS.map(dep => (
                  <li key={dep}><button type="button" onClick={() => { onDepartment(dep); setMobileNav(false) }}>{dep}</button></li>
                ))}
              </ul>
            </div>
            <div>
              <h4>Collections</h4>
              <ul>
                {COLLECTIONS.map(col => (
                  <li key={col.id}><button type="button" onClick={() => { onCollection(col.id); setMobileNav(false) }}>{col.label}</button></li>
                ))}
              </ul>
            </div>
            <div>
              <h4>Categories</h4>
              <ul>
                {CATEGORIES.map(cat => (
                  <li key={cat.id}><button type="button" onClick={() => { onCategory(cat.id); setMobileNav(false) }}>{cat.label}</button></li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}
    </header>
  )
}

const HERO_LOOKS = [
  { id: PRODUCTS.find(p => p.name.startsWith('Monolith')).id, color: 0 },
  { id: PRODUCTS.find(p => p.name.startsWith('Orbit')).id, color: 3 },
  { id: PRODUCTS.find(p => p.name.startsWith('Vector')).id, color: 1 },
  { id: PRODUCTS.find(p => p.name.startsWith('Runner')).id, color: 0 },
]

export function Hero({ onShop, onOpenProduct }) {
  const [look, setLook] = useState(0)
  const current = HERO_LOOKS[look]
  const product = PRODUCTS.find(p => p.id === current.id)
  const colorway = product.colorways[current.color]

  return (
    <section className="hero">
      <div className="shell hero__grid">
        <div>
          <p className="hero__eyebrow mono">Spring / Summer 2026 — Index 04</p>
          <h1>New forms,<br />rendered <em>live</em>.</h1>
          <p className="hero__lede">
            A clothing house with no photo studio. Every garment in the index is built as real 3D geometry,
            lit in a virtual studio and rendered in your browser — so you see the cut, the drape and the
            fabric before you ever open the box.
          </p>
          <div className="hero__cta">
            <button type="button" className="btn btn--primary" onClick={onShop}>
              Shop the index <Icon name="arrowRight" size={15} />
            </button>
            <button type="button" className="btn" onClick={() => onOpenProduct(product)}>
              Inspect this piece
            </button>
          </div>
          <div className="hero__stats">
            <div className="hero__stat"><strong>{PRODUCTS.length}</strong><span className="mono">Garments</span></div>
            <div className="hero__stat"><strong>{CATEGORIES.length}</strong><span className="mono">Categories</span></div>
            <div className="hero__stat"><strong>0</strong><span className="mono">Photographs</span></div>
            <div className="hero__stat"><strong>60s</strong><span className="mono">Returns window</span></div>
          </div>
        </div>

        <div className="hero__stage">
          <Viewer3D
            spec={garmentSpec(product, colorway, -0.5)}
            label={`${product.name} in ${colorway.name}`}
            autoRotate preset="obsidian" showHud={false}
          />
          <div style={{ position: 'absolute', left: 12, bottom: 12, right: 12, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {HERO_LOOKS.map((entry, index) => {
              const item = PRODUCTS.find(p => p.id === entry.id)
              return (
                <button
                  key={entry.id} type="button" className="viewer__chip" aria-pressed={index === look}
                  onClick={() => setLook(index)}
                >
                  {item.categoryLabel}
                </button>
              )
            })}
          </div>
        </div>
      </div>
    </section>
  )
}

export function Marquee() {
  const items = [
    'Live WebGL garment rendering', 'Free shipping over £150', '60-day returns',
    '15 categories', 'Responsibly sourced fabrics', 'Made in limited runs',
  ]
  return (
    <div className="marquee" aria-hidden="true">
      <div className="marquee__track">
        {[...items, ...items].map((item, index) => <span key={index}>{item} —</span>)}
      </div>
    </div>
  )
}

export function Footer({ onCategory, onCollection }) {
  return (
    <footer className="footer">
      <div className="shell">
        <div className="footer__grid">
          <div>
            <div className="header__logo" style={{ padding: 0, marginBottom: 12 }}>RARE<span style={{ color: 'var(--signal)' }}>·</span>FORM</div>
            <p className="muted" style={{ fontSize: 13.5, maxWidth: '38ch', lineHeight: 1.65 }}>
              A rendered clothing house. Garments are modelled as geometry, not photographed —
              which is why you can spin every single one.
            </p>
          </div>
          <div>
            <h4>Shop</h4>
            <ul>
              {CATEGORIES.slice(0, 6).map(cat => (
                <li key={cat.id}><button type="button" onClick={() => onCategory(cat.id)}>{cat.label}</button></li>
              ))}
            </ul>
          </div>
          <div>
            <h4>Collections</h4>
            <ul>
              {COLLECTIONS.map(col => (
                <li key={col.id}><button type="button" onClick={() => onCollection(col.id)}>{col.label}</button></li>
              ))}
            </ul>
          </div>
          <div>
            <h4>Help</h4>
            <ul>
              <li><button type="button">Shipping</button></li>
              <li><button type="button">Returns</button></li>
              <li><button type="button">Size guide</button></li>
              <li><button type="button">Contact</button></li>
            </ul>
          </div>
        </div>
        <div className="footer__bottom mono">
          <span>© 2026 RAREFORM Studio — demonstration storefront</span>
          <span>Rendered with WebGL · No product photography used</span>
        </div>
      </div>
    </footer>
  )
}
