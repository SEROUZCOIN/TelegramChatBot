import * as THREE from 'three'
import { fbm3 } from './noise.js'

// Every fabric gets a procedurally generated normal + roughness map. Nothing is
// fetched: the weave, twill, rib and grain are all drawn from a height function
// at load time, which keeps the whole storefront asset-free.

const TEX = 256
const cache = new Map()

function heightFor(kind, u, v) {
  const x = u * TEX
  const y = v * TEX
  switch (kind) {
    case 'denim': {
      const twill = Math.sin((x + y) * 0.9) * 0.5 + 0.5
      const grain = fbm3(u * 60, v * 60, 0, 11, 2) * 0.25
      return twill * 0.6 + grain
    }
    case 'knit':
    case 'wool': {
      const cellX = 10
      const cellY = 8
      const fx = (u * cellX) % 1
      const fy = (v * cellY) % 1
      const vee = 1 - Math.abs(fx * 2 - 1)
      const row = Math.sin(fy * Math.PI)
      return vee * row * 0.85 + fbm3(u * 30, v * 30, 0, 5, 2) * 0.15
    }
    case 'fleece':
      return fbm3(u * 26, v * 26, 0, 23, 4) * 0.5 + 0.5
    case 'corduroy': {
      const wale = Math.sin(u * Math.PI * 2 * 26) * 0.5 + 0.5
      return Math.pow(wale, 0.7) * 0.85 + fbm3(u * 40, v * 40, 0, 7, 2) * 0.15
    }
    case 'mesh': {
      const gx = Math.sin(u * Math.PI * 2 * 34)
      const gy = Math.sin(v * Math.PI * 2 * 34)
      return (gx * gy) * 0.5 + 0.5
    }
    case 'leather':
      return fbm3(u * 34, v * 34, 0, 3, 4) * 0.45 + 0.5
    case 'suede':
      return fbm3(u * 70, v * 70, 0, 17, 3) * 0.3 + 0.5
    case 'silk':
      return fbm3(u * 8, v * 22, 0, 29, 2) * 0.18 + 0.5
    case 'nylon': {
      const ripstop = (Math.abs(Math.sin(u * Math.PI * 2 * 16)) > 0.94 ? 1 : 0)
        + (Math.abs(Math.sin(v * Math.PI * 2 * 16)) > 0.94 ? 1 : 0)
      return ripstop * 0.35 + fbm3(u * 90, v * 90, 0, 41, 2) * 0.12 + 0.4
    }
    case 'canvas':
    case 'cotton':
    default: {
      const weave = (Math.sin(u * Math.PI * 2 * 64) * Math.sin(v * Math.PI * 2 * 64)) * 0.5 + 0.5
      return weave * 0.5 + fbm3(u * 50, v * 50, 0, 13, 2) * 0.3 + 0.2
    }
  }
}

function buildMaps(kind) {
  if (typeof document === 'undefined') return {}
  const heights = new Float32Array(TEX * TEX)
  for (let y = 0; y < TEX; y += 1) {
    for (let x = 0; x < TEX; x += 1) {
      heights[y * TEX + x] = heightFor(kind, x / TEX, y / TEX)
    }
  }

  const normalCanvas = document.createElement('canvas')
  normalCanvas.width = TEX
  normalCanvas.height = TEX
  const nCtx = normalCanvas.getContext('2d')
  const nImg = nCtx.createImageData(TEX, TEX)

  const roughCanvas = document.createElement('canvas')
  roughCanvas.width = TEX
  roughCanvas.height = TEX
  const rCtx = roughCanvas.getContext('2d')
  const rImg = rCtx.createImageData(TEX, TEX)

  const at = (x, y) => heights[((y + TEX) % TEX) * TEX + ((x + TEX) % TEX)]
  const strength = 2.2

  for (let y = 0; y < TEX; y += 1) {
    for (let x = 0; x < TEX; x += 1) {
      const dx = (at(x + 1, y) - at(x - 1, y)) * strength
      const dy = (at(x, y + 1) - at(x, y - 1)) * strength
      const len = Math.hypot(-dx, -dy, 1)
      const i = (y * TEX + x) * 4
      nImg.data[i] = ((-dx / len) * 0.5 + 0.5) * 255
      nImg.data[i + 1] = ((-dy / len) * 0.5 + 0.5) * 255
      nImg.data[i + 2] = (1 / len) * 255
      nImg.data[i + 3] = 255

      const h = at(x, y)
      const rough = 200 - h * 60
      rImg.data[i] = rough
      rImg.data[i + 1] = rough
      rImg.data[i + 2] = rough
      rImg.data[i + 3] = 255
    }
  }

  nCtx.putImageData(nImg, 0, 0)
  rCtx.putImageData(rImg, 0, 0)

  const normalMap = new THREE.CanvasTexture(normalCanvas)
  const roughnessMap = new THREE.CanvasTexture(roughCanvas)
  for (const t of [normalMap, roughnessMap]) {
    t.wrapS = THREE.RepeatWrapping
    t.wrapT = THREE.RepeatWrapping
    t.anisotropy = 4
  }
  return { normalMap, roughnessMap }
}

export function fabricMaps(kind) {
  if (!cache.has(kind)) cache.set(kind, buildMaps(kind))
  return cache.get(kind)
}

export const FABRICS = {
  cotton: { roughness: 0.88, sheen: 0.3, sheenRoughness: 0.7, repeat: 4, normalScale: 0.5, drape: 0.011 },
  jersey: { roughness: 0.84, sheen: 0.4, sheenRoughness: 0.6, repeat: 4, normalScale: 0.55, drape: 0.014 },
  canvas: { roughness: 0.92, sheen: 0.2, sheenRoughness: 0.8, repeat: 3.4, normalScale: 0.8, drape: 0.008 },
  denim: { roughness: 0.82, sheen: 0.15, sheenRoughness: 0.9, repeat: 5, normalScale: 0.75, drape: 0.01 },
  knit: { roughness: 0.94, sheen: 0.55, sheenRoughness: 0.55, repeat: 3, normalScale: 1.05, drape: 0.018 },
  wool: { roughness: 0.95, sheen: 0.65, sheenRoughness: 0.5, repeat: 2.6, normalScale: 1.1, drape: 0.02 },
  fleece: { roughness: 0.97, sheen: 0.6, sheenRoughness: 0.45, repeat: 3.2, normalScale: 0.9, drape: 0.022 },
  corduroy: { roughness: 0.9, sheen: 0.45, sheenRoughness: 0.6, repeat: 2.2, normalScale: 1.0, drape: 0.012 },
  leather: { roughness: 0.42, sheen: 0.1, sheenRoughness: 0.9, repeat: 3, normalScale: 0.45, clearcoat: 0.45, clearcoatRoughness: 0.5, drape: 0.006 },
  suede: { roughness: 0.96, sheen: 0.5, sheenRoughness: 0.4, repeat: 4, normalScale: 0.4, drape: 0.009 },
  nylon: { roughness: 0.4, sheen: 0.3, sheenRoughness: 0.4, repeat: 4.5, normalScale: 0.5, clearcoat: 0.6, clearcoatRoughness: 0.28, drape: 0.007 },
  silk: { roughness: 0.24, sheen: 0.95, sheenRoughness: 0.22, repeat: 3, normalScale: 0.3, clearcoat: 0.25, clearcoatRoughness: 0.3, drape: 0.016 },
  mesh: { roughness: 0.62, sheen: 0.3, sheenRoughness: 0.6, repeat: 6, normalScale: 0.7, drape: 0.008 },
}

export function fabricMaterial(colorHex, fabricKind = 'cotton', overrides = {}) {
  const preset = FABRICS[fabricKind] ?? FABRICS.cotton
  const maps = fabricMaps(fabricKind)
  const normalMap = maps.normalMap?.clone()
  const roughnessMap = maps.roughnessMap?.clone()
  const repeat = overrides.repeat ?? preset.repeat

  for (const t of [normalMap, roughnessMap]) {
    if (!t) continue
    t.wrapS = THREE.RepeatWrapping
    t.wrapT = THREE.RepeatWrapping
    t.repeat.set(repeat, repeat)
    t.needsUpdate = true
  }

  const color = new THREE.Color(colorHex)
  const sheenColor = color.clone().lerp(new THREE.Color('#ffffff'), 0.6)

  const material = new THREE.MeshPhysicalMaterial({
    color,
    roughness: preset.roughness,
    metalness: 0,
    sheen: preset.sheen,
    sheenRoughness: preset.sheenRoughness,
    sheenColor,
    clearcoat: preset.clearcoat ?? 0,
    clearcoatRoughness: preset.clearcoatRoughness ?? 0.4,
    normalMap: normalMap ?? null,
    roughnessMap: roughnessMap ?? null,
    side: THREE.DoubleSide,
    ...overrides.material,
  })
  if (normalMap) material.normalScale = new THREE.Vector2(preset.normalScale, preset.normalScale)
  return material
}

export function hardwareMaterial(tone = '#c8ccc4') {
  return new THREE.MeshPhysicalMaterial({
    color: new THREE.Color(tone),
    metalness: 0.95,
    roughness: 0.28,
    clearcoat: 0.6,
    clearcoatRoughness: 0.2,
  })
}

export function rubberMaterial(tone = '#101210') {
  return new THREE.MeshPhysicalMaterial({
    color: new THREE.Color(tone),
    metalness: 0,
    roughness: 0.72,
    clearcoat: 0.18,
  })
}
