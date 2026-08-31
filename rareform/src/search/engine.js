import { CATEGORIES, COLLECTIONS } from '../data/catalog.js'

// A small in-memory search engine: weighted field matching with a bounded edit
// distance for typos, plus faceted counts that exclude their own dimension so
// the numbers next to each filter stay truthful.

const STOP = new Set(['the', 'a', 'an', 'and', 'for', 'with', 'of', 'in', 'to'])

export function normalize(value) {
  return String(value)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9\s-]/g, ' ')
}

export function tokenize(value) {
  return normalize(value)
    .split(/[\s-]+/)
    .filter(token => token.length > 0 && !STOP.has(token))
}

// Bounded Levenshtein: returns maxDistance + 1 as soon as it is clearly worse,
// which keeps typo tolerance cheap across the whole catalogue.
function editDistance(a, b, max) {
  if (a === b) return 0
  if (Math.abs(a.length - b.length) > max) return max + 1
  let prev = new Array(b.length + 1)
  let curr = new Array(b.length + 1)
  for (let j = 0; j <= b.length; j += 1) prev[j] = j
  for (let i = 1; i <= a.length; i += 1) {
    curr[0] = i
    let best = curr[0]
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
      if (curr[j] < best) best = curr[j]
    }
    if (best > max) return max + 1
    const swap = prev
    prev = curr
    curr = swap
  }
  return prev[b.length]
}

const FIELD_WEIGHTS = [
  ['name', 10],
  ['categoryLabel', 6],
  ['tags', 5],
  ['department', 3],
  ['materialLabel', 3],
  ['colors', 4],
  ['fabric', 3],
  ['fit', 2],
  ['description', 1.4],
  ['details', 1.1],
  ['sku', 6],
]

export function buildIndex(products) {
  return products.map(product => {
    const fields = {
      name: tokenize(product.name),
      categoryLabel: tokenize(product.categoryLabel),
      tags: product.tags.flatMap(tokenize),
      department: tokenize(product.department),
      materialLabel: tokenize(product.materialLabel),
      colors: product.colorways.flatMap(cw => [...tokenize(cw.name), cw.family]),
      fabric: tokenize(product.fabric),
      fit: tokenize(product.fit),
      description: tokenize(product.description),
      details: product.details.flatMap(tokenize),
      sku: tokenize(product.sku),
    }
    return { product, fields, text: normalize(`${product.name} ${product.categoryLabel} ${product.tags.join(' ')}`) }
  })
}

function tokenScore(queryToken, fieldTokens) {
  let best = 0
  for (const token of fieldTokens) {
    if (token === queryToken) return 1
    if (token.startsWith(queryToken)) {
      best = Math.max(best, 0.86 + 0.1 * (queryToken.length / token.length))
      continue
    }
    if (queryToken.length >= 4 && token.includes(queryToken)) {
      best = Math.max(best, 0.62)
      continue
    }
    if (queryToken.length >= 4) {
      const max = queryToken.length >= 7 ? 2 : 1
      const distance = editDistance(queryToken, token, max)
      if (distance <= max) best = Math.max(best, 0.52 - 0.12 * (distance - 1))
    }
  }
  return best
}

export function scoreEntry(entry, queryTokens) {
  let total = 0
  let matchedTokens = 0
  for (const queryToken of queryTokens) {
    let tokenBest = 0
    for (const [field, weight] of FIELD_WEIGHTS) {
      const score = tokenScore(queryToken, entry.fields[field])
      if (score > 0) tokenBest = Math.max(tokenBest, score * weight)
    }
    if (tokenBest > 0) matchedTokens += 1
    total += tokenBest
  }
  if (matchedTokens < queryTokens.length) {
    // Every term should land somewhere; partial matches are heavily penalised
    // rather than dropped so a long query still returns its closest garments.
    total *= Math.pow(matchedTokens / queryTokens.length, 3)
  }
  return { score: total, matchedTokens }
}

export const DEFAULT_FILTERS = {
  departments: [],
  categories: [],
  groups: [],
  colors: [],
  sizes: [],
  fabrics: [],
  fits: [],
  collections: [],
  price: null,
  inStockOnly: false,
  sustainableOnly: false,
}

const PREDICATES = {
  departments: (p, values) => values.includes(p.department),
  categories: (p, values) => values.includes(p.category),
  groups: (p, values) => values.includes(p.group),
  colors: (p, values) => p.colorways.some(cw => values.includes(cw.family)),
  sizes: (p, values) => p.sizes.some(size => values.includes(size)),
  fabrics: (p, values) => values.includes(p.fabric),
  fits: (p, values) => values.includes(p.fit),
  collections: (p, values) => values.some(id => COLLECTIONS.find(col => col.id === id)?.test(p)),
}

function passesFilters(product, filters, skip = null) {
  for (const [key, predicate] of Object.entries(PREDICATES)) {
    if (key === skip) continue
    const values = filters[key]
    if (values?.length && !predicate(product, values)) return false
  }
  if (skip !== 'price' && filters.price) {
    if (product.price < filters.price[0] || product.price > filters.price[1]) return false
  }
  if (skip !== 'inStockOnly' && filters.inStockOnly && product.stock <= 0) return false
  if (skip !== 'sustainableOnly' && filters.sustainableOnly && !product.sustainable) return false
  return true
}

const SORTERS = {
  relevance: (a, b) => b.score - a.score || b.product.popularity - a.product.popularity,
  popular: (a, b) => b.product.popularity - a.product.popularity,
  newest: (a, b) => b.product.releasedAt.localeCompare(a.product.releasedAt),
  priceLow: (a, b) => a.product.price - b.product.price,
  priceHigh: (a, b) => b.product.price - a.product.price,
  rating: (a, b) => b.product.rating - a.product.rating || b.product.reviews - a.product.reviews,
}

export const SORT_OPTIONS = [
  { id: 'relevance', label: 'Best match' },
  { id: 'popular', label: 'Most popular' },
  { id: 'newest', label: 'Newest' },
  { id: 'priceLow', label: 'Price: low to high' },
  { id: 'priceHigh', label: 'Price: high to low' },
  { id: 'rating', label: 'Top rated' },
]

function countFacet(index, filters, key, valueOf) {
  const counts = new Map()
  for (const entry of index) {
    if (!passesFilters(entry.product, filters, key)) continue
    for (const value of valueOf(entry.product)) {
      counts.set(value, (counts.get(value) ?? 0) + 1)
    }
  }
  return counts
}

export function runSearch(index, { query = '', filters = DEFAULT_FILTERS, sort = 'relevance' } = {}) {
  const queryTokens = tokenize(query)
  const hasQuery = queryTokens.length > 0

  let scored = index.map(entry => {
    const { score } = hasQuery ? scoreEntry(entry, queryTokens) : { score: 0 }
    return { product: entry.product, score }
  })

  if (hasQuery) {
    const threshold = 0.8
    scored = scored.filter(item => item.score > threshold)
  }

  const matched = scored.filter(item => passesFilters(item.product, filters))
  const sorter = SORTERS[hasQuery && sort === 'relevance' ? 'relevance' : sort] ?? SORTERS.popular
  matched.sort(hasQuery ? sorter : (sort === 'relevance' ? SORTERS.popular : sorter))

  const pool = hasQuery ? index.filter(e => scored.some(s => s.product.id === e.product.id)) : index

  const facets = {
    departments: countFacet(pool, filters, 'departments', p => [p.department]),
    categories: countFacet(pool, filters, 'categories', p => [p.category]),
    groups: countFacet(pool, filters, 'groups', p => [p.group]),
    colors: countFacet(pool, filters, 'colors', p => [...new Set(p.colorways.map(cw => cw.family))]),
    sizes: countFacet(pool, filters, 'sizes', p => p.sizes),
    fabrics: countFacet(pool, filters, 'fabrics', p => [p.fabric]),
    fits: countFacet(pool, filters, 'fits', p => [p.fit]),
    collections: countFacet(pool, filters, 'collections', p => COLLECTIONS.filter(col => col.test(p)).map(col => col.id)),
  }

  return { results: matched.map(item => item.product), scores: matched, facets, hasQuery }
}

export function suggest(index, query, limit = 7) {
  const tokens = tokenize(query)
  if (!tokens.length) return []
  const seen = new Set()
  const out = []

  for (const category of CATEGORIES) {
    const { score } = scoreEntry({ fields: { name: tokenize(category.label), categoryLabel: [], tags: [], department: [], materialLabel: [], colors: [], fabric: [], fit: [], description: [], details: [], sku: [] } }, tokens)
    if (score > 4) out.push({ type: 'category', id: category.id, label: category.label, sub: category.group })
  }

  const products = index
    .map(entry => ({ entry, ...scoreEntry(entry, tokens) }))
    .filter(item => item.score > 1.5)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)

  for (const item of products) {
    if (seen.has(item.entry.product.id)) continue
    seen.add(item.entry.product.id)
    out.push({ type: 'product', id: item.entry.product.id, label: item.entry.product.name, sub: item.entry.product.categoryLabel, product: item.entry.product })
  }

  return out.slice(0, limit + 3)
}

export function highlight(text, query) {
  const tokens = tokenize(query).filter(t => t.length > 1)
  if (!tokens.length) return [{ text, hit: false }]
  const lower = normalize(text)
  const marks = new Array(text.length).fill(false)
  for (const token of tokens) {
    let from = 0
    while (from < lower.length) {
      const at = lower.indexOf(token, from)
      if (at === -1) break
      for (let i = at; i < at + token.length; i += 1) marks[i] = true
      from = at + token.length
    }
  }
  const parts = []
  let buffer = ''
  let current = marks[0] ?? false
  for (let i = 0; i < text.length; i += 1) {
    if (marks[i] === current) buffer += text[i]
    else {
      parts.push({ text: buffer, hit: current })
      buffer = text[i]
      current = marks[i]
    }
  }
  if (buffer) parts.push({ text: buffer, hit: current })
  return parts
}
