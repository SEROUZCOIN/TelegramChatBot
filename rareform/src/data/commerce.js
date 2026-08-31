import { PRODUCTS } from './catalog.js'
import { mulberry32 } from '../three/noise.js'

// Seed orders and customers are generated deterministically from the catalogue,
// so the admin dashboard has believable history without shipping a fixture dump.

const NAMES = [
  ['Alex Moreno', 'alex.moreno@example.com', 'London'],
  ['Priya Raman', 'priya.raman@example.com', 'Manchester'],
  ['Tomas Nowak', 't.nowak@example.com', 'Kraków'],
  ['Yuki Tanaka', 'yuki.tanaka@example.com', 'Osaka'],
  ['Ines Duarte', 'ines.duarte@example.com', 'Lisbon'],
  ['Sam Okafor', 'sam.okafor@example.com', 'Lagos'],
  ['Marta Weiss', 'marta.weiss@example.com', 'Berlin'],
  ['Jordan Blake', 'jordan.blake@example.com', 'Bristol'],
  ['Noor Haddad', 'noor.haddad@example.com', 'Amsterdam'],
  ['Elena Rossi', 'elena.rossi@example.com', 'Milan'],
  ['Chris Vance', 'chris.vance@example.com', 'Dublin'],
  ['Aiko Mori', 'aiko.mori@example.com', 'Kyoto'],
]

export const ORDER_STATES = ['Pending', 'Paid', 'Packing', 'Shipped', 'Delivered', 'Refunded']

const dayStamp = daysAgo => {
  const date = new Date('2026-08-31T12:00:00Z')
  date.setUTCDate(date.getUTCDate() - daysAgo)
  return date.toISOString().slice(0, 10)
}

export function seedCommerce() {
  const random = mulberry32(20260831)
  const customers = NAMES.map(([name, email, city], index) => ({
    id: `cust-${String(index + 1).padStart(3, '0')}`,
    name,
    email,
    city,
    joinedAt: dayStamp(40 + Math.floor(random() * 320)),
  }))

  const orders = []
  for (let i = 0; i < 46; i += 1) {
    const customer = customers[Math.floor(random() * customers.length)]
    const daysAgo = Math.floor(random() * 28)
    const itemCount = 1 + Math.floor(random() * 3)
    const items = []
    for (let j = 0; j < itemCount; j += 1) {
      const product = PRODUCTS[Math.floor(random() * PRODUCTS.length)]
      const colorway = product.colorways[Math.floor(random() * product.colorways.length)]
      const size = product.sizes[Math.floor(random() * product.sizes.length)]
      items.push({ productId: product.id, name: product.name, size, colorName: colorway.name, qty: 1 + Math.floor(random() * 2), price: product.price })
    }
    const total = items.reduce((sum, item) => sum + item.price * item.qty, 0)
    // Recent orders sit early in the pipeline, older ones have landed.
    const status = daysAgo < 2 ? 'Paid'
      : daysAgo < 4 ? 'Packing'
        : daysAgo < 9 ? 'Shipped'
          : random() < 0.06 ? 'Refunded' : 'Delivered'
    orders.push({
      id: `RF-${11400 + i}`,
      customerId: customer.id,
      customer: customer.name,
      email: customer.email,
      city: customer.city,
      placedAt: dayStamp(daysAgo),
      daysAgo,
      items,
      total,
      status,
    })
  }
  orders.sort((a, b) => a.daysAgo - b.daysAgo)
  return { orders, customers }
}

export const DEFAULT_SETTINGS = {
  storeName: 'RAREFORM',
  currency: 'GBP',
  freeShippingOver: 150,
  standardShipping: 8,
  lowStockThreshold: 10,
  returnsWindow: 60,
  promos: [
    { code: 'FORM10', rate: 0.1, active: true },
    { code: 'STUDIO20', rate: 0.2, active: true },
  ],
}

export const DEFAULT_STUDIO = {
  preset: 'hologram',
  cardPreset: 'studio',
  angle: -0.42,
  autoRotate: true,
  bloom: true,
  bloomStrength: 0.45,
  grid: true,
  exposure: 1,
}
