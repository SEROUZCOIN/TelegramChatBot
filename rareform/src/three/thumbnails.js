import * as THREE from 'three'
import { buildGarment, recolorGarment, disposeGarment } from './garments.js'
import { createRenderer, createStudioScene, createCamera, hasWebGL } from './studio.js'

// Product cards are not photographs — each one is rendered off-screen by the
// same WebGL pipeline as the product page, then cached as a data URL. Work is
// queued a couple of frames at a time so the grid never blocks on rendering.

const WIDTH = 520
const HEIGHT = 650

let renderer = null
let studio = null
let camera = null
const geometryCache = new Map()
const imageCache = new Map()
const pending = new Map()
const queue = []
let running = false
let mimeType = null

function pickMime() {
  if (mimeType) return mimeType
  const c = document.createElement('canvas')
  c.width = 2
  c.height = 2
  mimeType = c.toDataURL('image/webp').startsWith('data:image/webp') ? 'image/webp' : 'image/png'
  return mimeType
}

function boot() {
  if (renderer) return true
  if (!hasWebGL()) return false
  const canvas = document.createElement('canvas')
  canvas.width = WIDTH
  canvas.height = HEIGHT
  renderer = createRenderer(canvas, { alpha: true, antialias: true, dpr: Math.min(2, window.devicePixelRatio || 1) })
  renderer.setSize(WIDTH, HEIGHT, false)
  studio = createStudioScene(renderer, 'studio')
  camera = createCamera(WIDTH / HEIGHT)
  return true
}

function garmentFor(spec) {
  const key = `${spec.kind}|${spec.fit}|${spec.fabric}|${spec.seed}`
  if (!geometryCache.has(key)) {
    if (geometryCache.size > 26) {
      const oldest = geometryCache.keys().next().value
      const stale = geometryCache.get(oldest)
      disposeGarment(stale)
      geometryCache.delete(oldest)
    }
    geometryCache.set(key, buildGarment(spec))
  }
  return geometryCache.get(key)
}

export function thumbnailKey(spec) {
  return `${spec.kind}|${spec.fit}|${spec.fabric}|${spec.seed}|${spec.color}|${spec.accent ?? ''}|${spec.angle ?? 0}`
}

function renderNow(spec) {
  const garment = garmentFor(spec)
  recolorGarment(garment, { color: spec.color, accent: spec.accent })
  garment.rotation.set(0, spec.angle ?? -0.42, 0)

  studio.scene.add(garment)
  renderer.render(studio.scene, camera)
  const url = renderer.domElement.toDataURL(pickMime(), 0.86)
  studio.scene.remove(garment)
  return url
}

function pump() {
  if (!queue.length) {
    running = false
    return
  }
  running = true
  const budget = 2
  for (let i = 0; i < budget && queue.length; i += 1) {
    const job = queue.shift()
    if (imageCache.has(job.key)) {
      job.resolvers.forEach(fn => fn(imageCache.get(job.key)))
      pending.delete(job.key)
      continue
    }
    let url = null
    try {
      url = renderNow(job.spec)
    } catch (error) {
      console.warn('thumbnail render failed', error)
    }
    if (url) imageCache.set(job.key, url)
    job.resolvers.forEach(fn => fn(url))
    pending.delete(job.key)
  }
  requestAnimationFrame(pump)
}

export function cachedThumbnail(spec) {
  return imageCache.get(thumbnailKey(spec)) ?? null
}

export function requestThumbnail(spec, { priority = false } = {}) {
  const key = thumbnailKey(spec)
  if (imageCache.has(key)) return Promise.resolve(imageCache.get(key))
  if (!boot()) return Promise.resolve(null)

  if (pending.has(key)) {
    const job = pending.get(key)
    if (priority) {
      const index = queue.indexOf(job)
      if (index > 0) {
        queue.splice(index, 1)
        queue.unshift(job)
      }
    }
    return new Promise(resolve => job.resolvers.push(resolve))
  }

  const job = { key, spec, resolvers: [] }
  pending.set(key, job)
  if (priority) queue.unshift(job)
  else queue.push(job)

  const promise = new Promise(resolve => job.resolvers.push(resolve))
  if (!running) requestAnimationFrame(pump)
  return promise
}

export function prefetchThumbnails(specs) {
  specs.forEach(spec => requestThumbnail(spec))
}

export function thumbnailSupported() {
  return hasWebGL()
}

export function clearThumbnailCaches() {
  imageCache.clear()
  for (const g of geometryCache.values()) disposeGarment(g)
  geometryCache.clear()
}

export { THREE }
