import { useCallback, useEffect, useMemo, useState } from 'react'
import { Header, Hero, Marquee, Footer } from './components/Chrome.jsx'
import ProductCard from './components/ProductCard.jsx'
import ProductPage from './components/ProductPage.jsx'
import FilterRail from './components/FilterRail.jsx'
import CartDrawer from './components/CartDrawer.jsx'
import CommandPalette from './components/CommandPalette.jsx'
import Checkout from './components/Checkout.jsx'
import AdminApp from './admin/AdminApp.jsx'
import { CATEGORIES, COLLECTIONS, PRICE_BOUNDS } from './data/catalog.js'
import { buildIndex, runSearch, DEFAULT_FILTERS, SORT_OPTIONS } from './search/engine.js'
import { prefetchThumbnails } from './three/thumbnails.js'
import { garmentSpec } from './data/catalog.js'
import { useShop } from './store/ShopContext.jsx'
import { usePersistentState, useToasts, useMediaQuery, lineKey, money } from './lib/store.js'
import { Icon } from './lib/icons.jsx'

// When this page is embedded somewhere that states a theme, follow it on first
// load. Otherwise the house style is dark.
function initialTheme() {
  const stated = document.documentElement.dataset.theme
  return stated === 'light' || stated === 'dark' ? stated : 'dark'
}

export default function App() {
  const { products: PRODUCTS, studio, placeOrder } = useShop()
  const searchIndex = useMemo(() => buildIndex(PRODUCTS), [PRODUCTS])
  const [theme, setTheme] = usePersistentState('rf.theme', initialTheme)
  const [mode, setMode] = useState('store')
  const [view, setView] = useState({ name: 'shop' })
  const [query, setQuery] = useState('')
  const [filters, setFilters] = useState(DEFAULT_FILTERS)
  const [sort, setSort] = useState('relevance')
  const [cart, setCart] = usePersistentState('rf.cart.v2', [])
  const [wishlist, setWishlist] = usePersistentState('rf.wishlist.v2', [])
  const [recents, setRecents] = usePersistentState('rf.recents', [])
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [cartOpen, setCartOpen] = useState(false)
  const [railOpen, setRailOpen] = useState(false)
  const [checkout, setCheckout] = useState(null)
  const { toasts, push, dismiss } = useToasts()
  const isMobile = useMediaQuery('(max-width: 900px)')

  useEffect(() => { document.documentElement.dataset.theme = theme }, [theme])

  const { results, facets, hasQuery } = useMemo(
    () => runSearch(searchIndex, { query, filters, sort }),
    [searchIndex, query, filters, sort],
  )

  // Warm the first screen of renders so the grid is not blank on arrival.
  useEffect(() => {
    prefetchThumbnails(results.slice(0, 8).map(p => garmentSpec(p, p.colorways[0])))
  }, [results])

  useEffect(() => {
    const onKey = event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setPaletteOpen(true)
      }
      if (event.key === '/' && !/^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName ?? '')) {
        event.preventDefault()
        setPaletteOpen(true)
      }
      if (event.key === 'Escape') {
        setCartOpen(false)
        setRailOpen(false)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => { window.scrollTo({ top: 0, behavior: 'instant' }) }, [view])

  const activeFilterChips = useMemo(() => {
    const chips = []
    const label = {
      collections: id => COLLECTIONS.find(c => c.id === id)?.label,
      categories: id => CATEGORIES.find(c => c.id === id)?.label,
    }
    for (const key of ['collections', 'departments', 'categories', 'colors', 'sizes', 'fabrics', 'fits']) {
      for (const value of filters[key]) {
        chips.push({ key, value, label: label[key]?.(value) ?? String(value) })
      }
    }
    if (filters.price && filters.price[1] < PRICE_BOUNDS.max) {
      chips.push({ key: 'price', value: null, label: `Under ${money(filters.price[1])}` })
    }
    if (filters.inStockOnly) chips.push({ key: 'inStockOnly', value: null, label: 'In stock' })
    if (filters.sustainableOnly) chips.push({ key: 'sustainableOnly', value: null, label: 'Responsible' })
    return chips
  }, [filters])

  const removeChip = chip => setFilters(current => {
    if (chip.key === 'price') return { ...current, price: null }
    if (chip.key === 'inStockOnly' || chip.key === 'sustainableOnly') return { ...current, [chip.key]: false }
    return { ...current, [chip.key]: current[chip.key].filter(v => v !== chip.value) }
  })

  const goShop = useCallback(patch => {
    setView({ name: 'shop' })
    setFilters(current => ({ ...DEFAULT_FILTERS, ...patch }))
    setQuery('')
  }, [])

  const openProduct = useCallback((product, colorIndex = 0) => {
    setView({ name: 'product', id: product.id, color: colorIndex })
  }, [])

  const addToCart = useCallback((product, size, colorway, qty = 1) => {
    const key = lineKey(product.id, size, colorway.name)
    setCart(current => {
      const existing = current.find(line => line.key === key)
      if (existing) {
        return current.map(line => (line.key === key ? { ...line, qty: Math.min(9, line.qty + qty) } : line))
      }
      return [...current, { key, productId: product.id, size, colorName: colorway.name, qty }]
    })
    push(`${product.name} · ${size} added to bag`, { action: 'View bag' })
    setCartOpen(true)
  }, [push, setCart])

  const toggleWish = useCallback(product => {
    setWishlist(current => {
      const has = current.includes(product.id)
      push(has ? `Removed ${product.name}` : `Saved ${product.name}`)
      return has ? current.filter(id => id !== product.id) : [...current, product.id]
    })
  }, [push, setWishlist])

  const cartLines = useMemo(() => cart.map(line => {
    const product = PRODUCTS.find(p => p.id === line.productId)
    if (!product) return null
    const colorway = product.colorways.find(cw => cw.name === line.colorName) ?? product.colorways[0]
    return { ...line, product, colorway }
  }).filter(Boolean), [cart, PRODUCTS])

  const cartCount = cartLines.reduce((sum, line) => sum + line.qty, 0)

  const runQuery = term => {
    setQuery(term)
    setView({ name: 'shop' })
    setSort('relevance')
    if (term.trim()) {
      setRecents(current => [term, ...current.filter(item => item !== term)].slice(0, 6))
    }
  }

  const wishProducts = PRODUCTS.filter(p => wishlist.includes(p.id))
  const showHero = view.name === 'shop' && !hasQuery && activeFilterChips.length === 0
  const product = view.name === 'product' ? PRODUCTS.find(p => p.id === view.id) : null

  if (mode === 'admin') {
    return (
      <>
        <AdminApp onExit={() => setMode('store')} notify={push} />
        <div className="toasts">
          {toasts.map(toast => (
            <div className="toast" key={toast.id} role="status">
              <Icon name="check" size={15} strokeWidth={2.4} />
              <span>{toast.message}</span>
              <button type="button" onClick={() => dismiss(toast.id)}>Dismiss</button>
            </div>
          ))}
        </div>
      </>
    )
  }

  return (
    <>
      <a href="#main" className="sr">Skip to content</a>

      <Header
        cartCount={cartCount} wishCount={wishlist.length} theme={theme} activeView={view.name}
        onTheme={() => setTheme(t => (t === 'dark' ? 'light' : 'dark'))}
        onSearch={() => setPaletteOpen(true)}
        onHome={() => goShop()}
        onCategory={(id, department) => goShop({
          categories: [id],
          departments: department && department !== 'Unisex' ? [department] : [],
        })}
        onCollection={id => goShop({ collections: [id] })}
        onDepartment={dep => goShop({ departments: [dep] })}
        onCart={() => setCartOpen(true)}
        onWishlist={() => setView({ name: 'wishlist' })}
        onAdmin={() => setMode('admin')}
      />

      <main id="main">
        {view.name === 'product' && product && (
          <ProductPage
            product={product} initialColor={view.color}
            wished={wishlist.includes(product.id)} onWish={toggleWish}
            onAdd={addToCart} onBack={() => goShop()} onOpenProduct={openProduct}
          />
        )}

        {view.name === 'wishlist' && (
          <div className="shell section">
            <div className="section__head">
              <div>
                <h2>Wishlist</h2>
                <p>{wishProducts.length} saved {wishProducts.length === 1 ? 'piece' : 'pieces'}.</p>
              </div>
              <button type="button" className="btn" onClick={() => goShop()}>Back to shop</button>
            </div>
            {wishProducts.length === 0
              ? (
                <div className="empty">
                  <h3>Nothing saved yet</h3>
                  <p>Tap the heart on any garment to keep it here between visits.</p>
                  <button type="button" className="btn btn--primary" onClick={() => goShop()}>Browse the index</button>
                </div>
              )
              : (
                <div className="grid">
                  {wishProducts.map(item => (
                    <ProductCard
                      key={item.id} product={item} wished onWish={toggleWish} onOpen={openProduct}
                      onQuickAdd={(p, s, c) => addToCart(p, s, c, 1)}
                    />
                  ))}
                </div>
              )}
          </div>
        )}

        {view.name === 'shop' && (
          <>
            {showHero && (
              <>
                <Hero
                  onShop={() => document.getElementById('index')?.scrollIntoView({ behavior: 'smooth' })}
                  onOpenProduct={openProduct} studio={studio}
                />
                <Marquee />
                <section className="shell section" style={{ paddingBottom: 0 }}>
                  <div className="section__head">
                    <div>
                      <h2>Every category</h2>
                      <p>Fifteen categories, all modelled from the same geometry engine — tops, outerwear, bottoms, womenswear and accessories.</p>
                    </div>
                  </div>
                  <div className="railstrip">
                    {CATEGORIES.map(cat => (
                      <button key={cat.id} type="button" className="catcard" onClick={() => goShop({ categories: [cat.id] })}>
                        <div className="catcard__swatch" />
                        <strong>{cat.label}</strong>
                        <span>{PRODUCTS.filter(p => p.category === cat.id).length} pieces</span>
                      </button>
                    ))}
                  </div>
                </section>
              </>
            )}

            <div className="shell shop" id="index">
              <FilterRail
                facets={facets} filters={filters} setFilters={setFilters} bounds={PRICE_BOUNDS}
                resultCount={results.length} open={!isMobile || railOpen}
                onClose={() => setRailOpen(false)} onClear={() => { setFilters(DEFAULT_FILTERS); setQuery('') }}
              />

              <section>
                <div className="toolbar">
                  <button type="button" className="btn btn--sm filter-fab" onClick={() => setRailOpen(true)}>
                    <Icon name="sliders" size={14} /> Filters{activeFilterChips.length ? ` (${activeFilterChips.length})` : ''}
                  </button>
                  <span className="toolbar__count" role="status" aria-live="polite">
                    {results.length} {results.length === 1 ? 'garment' : 'garments'}
                    {hasQuery && <> for “{query}”</>}
                  </span>
                  <div className="toolbar__spacer" />
                  {hasQuery && (
                    <button type="button" className="chip" onClick={() => setQuery('')}>
                      Clear search <Icon name="x" size={11} />
                    </button>
                  )}
                  <label className="sr" htmlFor="sort">Sort by</label>
                  <select id="sort" className="select" value={sort} onChange={e => setSort(e.target.value)}>
                    {SORT_OPTIONS.map(option => <option key={option.id} value={option.id}>{option.label}</option>)}
                  </select>
                </div>

                {activeFilterChips.length > 0 && (
                  <div className="chips" style={{ marginBottom: 20 }}>
                    {activeFilterChips.map(chip => (
                      <button key={`${chip.key}-${chip.value}`} type="button" className="chip" onClick={() => removeChip(chip)}>
                        {chip.label} <Icon name="x" size={11} />
                      </button>
                    ))}
                    <button type="button" className="chip" onClick={() => setFilters(DEFAULT_FILTERS)} style={{ borderStyle: 'dashed' }}>
                      Clear all
                    </button>
                  </div>
                )}

                {results.length === 0
                  ? (
                    <div className="empty">
                      <h3>No garments match</h3>
                      <p>
                        {hasQuery
                          ? <>Nothing in the index matches “{query}” with these filters.</>
                          : <>These filters are too narrow. Try loosening one.</>}
                      </p>
                      <button type="button" className="btn btn--primary" onClick={() => { setFilters(DEFAULT_FILTERS); setQuery('') }}>
                        Reset everything
                      </button>
                    </div>
                  )
                  : (
                    <div className="grid">
                      {results.map(item => (
                        <ProductCard
                          key={item.id} product={item} query={query}
                          wished={wishlist.includes(item.id)} onWish={toggleWish}
                          onOpen={openProduct} onQuickAdd={(p, s, c) => addToCart(p, s, c, 1)}
                        />
                      ))}
                    </div>
                  )}
              </section>
            </div>
          </>
        )}
      </main>

      <Footer
        onCategory={id => goShop({ categories: [id] })}
        onCollection={id => goShop({ collections: [id] })}
        onAdmin={() => setMode('admin')}
      />

      <CartDrawer
        open={cartOpen} lines={cartLines} onClose={() => setCartOpen(false)}
        onQty={(key, delta) => setCart(current => current
          .map(line => (line.key === key ? { ...line, qty: Math.max(0, Math.min(9, line.qty + delta)) } : line))
          .filter(line => line.qty > 0))}
        onRemove={key => setCart(current => current.filter(line => line.key !== key))}
        onCheckout={total => { setCartOpen(false); setCheckout(total) }}
      />

      <CommandPalette
        open={paletteOpen} index={searchIndex} recents={recents}
        onClose={() => setPaletteOpen(false)}
        onSearch={runQuery}
        onOpenProduct={openProduct}
        onCategory={id => goShop({ categories: [id] })}
        onCollection={id => goShop({ collections: [id] })}
      />

      <Checkout
        open={checkout !== null} total={checkout ?? 0}
        onClose={() => setCheckout(null)}
        onComplete={() => {
          const order = placeOrder(cartLines, checkout ?? 0)
          setCart([])
          push(`Order ${order.id} placed — visible in the admin panel.`)
        }}
      />

      <div className="toasts">
        {toasts.map(toast => (
          <div className="toast" key={toast.id} role="status">
            <Icon name="check" size={15} strokeWidth={2.4} />
            <span>{toast.message}</span>
            <button type="button" onClick={() => dismiss(toast.id)}>Dismiss</button>
          </div>
        ))}
      </div>
    </>
  )
}
