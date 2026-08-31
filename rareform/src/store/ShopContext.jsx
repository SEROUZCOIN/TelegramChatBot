import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { PRODUCTS } from '../data/catalog.js'
import { DEFAULT_SETTINGS, DEFAULT_STUDIO, seedCommerce } from '../data/commerce.js'
import { usePersistentState, setCurrency } from '../lib/store.js'
import { setThumbnailStudio } from '../three/thumbnails.js'

// One store behind both the storefront and the admin panel. Anything the admin
// edits — a product, a colourway, the render settings, the promo codes — is the
// same state the shop reads, so changes land immediately on the shop side.

const ShopContext = createContext(null)

export function ShopProvider({ children }) {
  const seed = useMemo(seedCommerce, [])
  const [products, setProducts] = usePersistentState('rf.products.v3', PRODUCTS)
  const [orders, setOrders] = usePersistentState('rf.orders.v3', seed.orders)
  const [customers] = usePersistentState('rf.customers.v3', seed.customers)
  const [settings, setSettings] = usePersistentState('rf.settings.v1', DEFAULT_SETTINGS)
  const [studio, setStudio] = usePersistentState('rf.studio.v1', DEFAULT_STUDIO)

  useEffect(() => { setCurrency(settings.currency) }, [settings.currency])
  useEffect(() => { setThumbnailStudio(studio.cardPreset, studio.angle) }, [studio.cardPreset, studio.angle])

  const upsertProduct = useCallback(next => {
    setProducts(current => {
      const index = current.findIndex(p => p.id === next.id)
      if (index === -1) return [next, ...current]
      const copy = [...current]
      copy[index] = next
      return copy
    })
  }, [setProducts])

  const removeProduct = useCallback(id => {
    setProducts(current => current.filter(p => p.id !== id))
  }, [setProducts])

  const adjustStock = useCallback((id, delta) => {
    setProducts(current => current.map(p => (p.id === id ? { ...p, stock: Math.max(0, p.stock + delta) } : p)))
  }, [setProducts])

  const setOrderStatus = useCallback((id, status) => {
    setOrders(current => current.map(order => (order.id === id ? { ...order, status } : order)))
  }, [setOrders])

  const placeOrder = useCallback((lines, total) => {
    const id = `RF-${11500 + Math.floor(Math.random() * 8999)}`
    const order = {
      id,
      customerId: 'cust-you',
      customer: 'You (demo checkout)',
      email: 'demo@rareform.studio',
      city: '—',
      placedAt: new Date().toISOString().slice(0, 10),
      daysAgo: 0,
      items: lines.map(line => ({
        productId: line.product.id, name: line.product.name, size: line.size,
        colorName: line.colorway.name, qty: line.qty, price: line.product.price,
      })),
      total,
      status: 'Paid',
    }
    setOrders(current => [order, ...current])
    setProducts(current => current.map(product => {
      const sold = lines.filter(line => line.product.id === product.id).reduce((n, line) => n + line.qty, 0)
      return sold ? { ...product, stock: Math.max(0, product.stock - sold) } : product
    }))
    return order
  }, [setOrders, setProducts])

  const resetDemo = useCallback(() => {
    const fresh = seedCommerce()
    setProducts(PRODUCTS)
    setOrders(fresh.orders)
    setSettings(DEFAULT_SETTINGS)
    setStudio(DEFAULT_STUDIO)
  }, [setProducts, setOrders, setSettings, setStudio])

  const value = useMemo(() => ({
    products, setProducts, upsertProduct, removeProduct, adjustStock,
    orders, setOrderStatus, placeOrder,
    customers, settings, setSettings, studio, setStudio, resetDemo,
  }), [products, setProducts, upsertProduct, removeProduct, adjustStock, orders,
    setOrderStatus, placeOrder, customers, settings, setSettings, studio, setStudio, resetDemo])

  return <ShopContext.Provider value={value}>{children}</ShopContext.Provider>
}

export function useShop() {
  const value = useContext(ShopContext)
  if (!value) throw new Error('useShop must be used inside ShopProvider')
  return value
}

export function useAdminMetrics() {
  const { orders, products, settings, customers } = useShop()
  return useMemo(() => {
    const live = orders.filter(order => order.status !== 'Refunded')
    const revenue = live.reduce((sum, order) => sum + order.total, 0)
    const units = live.reduce((sum, order) => sum + order.items.reduce((n, item) => n + item.qty, 0), 0)
    const refunded = orders.filter(order => order.status === 'Refunded').reduce((sum, o) => sum + o.total, 0)

    const byDay = new Map()
    for (const order of live) {
      byDay.set(order.daysAgo, (byDay.get(order.daysAgo) ?? 0) + order.total)
    }
    const series = Array.from({ length: 28 }, (_, i) => ({ daysAgo: 27 - i, value: byDay.get(27 - i) ?? 0 }))

    const soldByProduct = new Map()
    for (const order of live) {
      for (const item of order.items) {
        const entry = soldByProduct.get(item.productId) ?? { units: 0, revenue: 0 }
        entry.units += item.qty
        entry.revenue += item.price * item.qty
        soldByProduct.set(item.productId, entry)
      }
    }
    const top = [...soldByProduct.entries()]
      .map(([id, entry]) => ({ product: products.find(p => p.id === id), ...entry }))
      .filter(row => row.product)
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, 6)

    const lowStock = products
      .filter(p => p.stock <= settings.lowStockThreshold)
      .sort((a, b) => a.stock - b.stock)

    const recentWeek = live.filter(o => o.daysAgo < 7).reduce((s, o) => s + o.total, 0)
    const priorWeek = live.filter(o => o.daysAgo >= 7 && o.daysAgo < 14).reduce((s, o) => s + o.total, 0)
    const trend = priorWeek === 0 ? 0 : ((recentWeek - priorWeek) / priorWeek) * 100

    return {
      revenue,
      refunded,
      orderCount: live.length,
      units,
      aov: live.length ? revenue / live.length : 0,
      series,
      top,
      lowStock,
      trend,
      customerCount: customers.length,
      openOrders: orders.filter(o => ['Pending', 'Paid', 'Packing'].includes(o.status)).length,
    }
  }, [orders, products, settings.lowStockThreshold, customers])
}
