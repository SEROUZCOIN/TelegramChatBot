// Deterministic value noise. Used to give flat lofted garment surfaces the
// small irregularities that read as fabric rather than plastic.

function hash3(x, y, z, seed) {
  let h = x * 374761393 + y * 668265263 + z * 2147483647 + seed * 1013904223
  h = (h ^ (h >>> 13)) >>> 0
  h = Math.imul(h, 1274126177) >>> 0
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295
}

const fade = t => t * t * t * (t * (t * 6 - 15) + 10)
const lerp = (a, b, t) => a + (b - a) * t

export function valueNoise3(x, y, z, seed = 1) {
  const xi = Math.floor(x)
  const yi = Math.floor(y)
  const zi = Math.floor(z)
  const xf = fade(x - xi)
  const yf = fade(y - yi)
  const zf = fade(z - zi)

  const c = (dx, dy, dz) => hash3(xi + dx, yi + dy, zi + dz, seed)

  const x00 = lerp(c(0, 0, 0), c(1, 0, 0), xf)
  const x10 = lerp(c(0, 1, 0), c(1, 1, 0), xf)
  const x01 = lerp(c(0, 0, 1), c(1, 0, 1), xf)
  const x11 = lerp(c(0, 1, 1), c(1, 1, 1), xf)

  return lerp(lerp(x00, x10, yf), lerp(x01, x11, yf), zf) * 2 - 1
}

export function fbm3(x, y, z, seed = 1, octaves = 3) {
  let sum = 0
  let amp = 1
  let norm = 0
  let freq = 1
  for (let i = 0; i < octaves; i += 1) {
    sum += valueNoise3(x * freq, y * freq, z * freq, seed + i * 37) * amp
    norm += amp
    amp *= 0.5
    freq *= 2.07
  }
  return sum / norm
}

// Small seeded PRNG so a product always renders identically between sessions.
export function mulberry32(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
