import * as THREE from 'three'
import { fbm3 } from './noise.js'

// Superellipse cross-section. n = 2 gives an ellipse, higher n squares the
// shape off — garments sit between the two, which is why every panel here is
// lofted from superellipses rather than cylinders.
function sectionPoint(t, w, d, n, out) {
  const c = Math.cos(t)
  const s = Math.sin(t)
  const p = 2 / n
  out.x = Math.sign(c) * Math.pow(Math.abs(c), p) * w
  out.y = Math.sign(s) * Math.pow(Math.abs(s), p) * d
  return out
}

function averageSeamNormals(geometry, rings, radial) {
  const normal = geometry.attributes.normal
  const stride = radial + 1
  for (let i = 0; i < rings; i += 1) {
    const a = i * stride
    const b = a + radial
    const nx = (normal.getX(a) + normal.getX(b)) * 0.5
    const ny = (normal.getY(a) + normal.getY(b)) * 0.5
    const nz = (normal.getZ(a) + normal.getZ(b)) * 0.5
    const len = Math.hypot(nx, ny, nz) || 1
    normal.setXYZ(a, nx / len, ny / len, nz / len)
    normal.setXYZ(b, nx / len, ny / len, nz / len)
  }
  normal.needsUpdate = true
}

function buildCap(positions, normals, uvs, indices, ring, flip) {
  const base = positions.length / 3
  let cx = 0
  let cy = 0
  let cz = 0
  for (const v of ring) {
    cx += v.x
    cy += v.y
    cz += v.z
  }
  cx /= ring.length
  cy /= ring.length
  cz /= ring.length

  positions.push(cx, cy, cz)
  normals.push(0, flip ? -1 : 1, 0)
  uvs.push(0.5, 0.5)

  for (const v of ring) {
    positions.push(v.x, v.y, v.z)
    normals.push(0, flip ? -1 : 1, 0)
    uvs.push(0.5, 0.5)
  }

  for (let j = 0; j < ring.length - 1; j += 1) {
    const a = base
    const b = base + 1 + j
    const c = base + 1 + j + 1
    if (flip) indices.push(a, c, b)
    else indices.push(a, b, c)
  }
}

/**
 * Loft a surface through a stack of horizontal cross-sections.
 * Each section: { y, w, d, n?, cx?, cz?, rot? }
 */
export function loftSections(sections, options = {}) {
  const { radial = 56, capStart = false, capEnd = false, vRepeat = 1 } = options
  const rings = sections.length
  const stride = radial + 1

  const positions = []
  const normals = []
  const uvs = []
  const indices = []
  const tmp = new THREE.Vector2()

  const ringPoints = []

  for (let i = 0; i < rings; i += 1) {
    const s = sections[i]
    const n = s.n ?? 2.6
    const cx = s.cx ?? 0
    const cz = s.cz ?? 0
    const rot = s.rot ?? 0
    const cosR = Math.cos(rot)
    const sinR = Math.sin(rot)
    const points = []

    for (let j = 0; j <= radial; j += 1) {
      const t = (j / radial) * Math.PI * 2
      sectionPoint(t, s.w, s.d, n, tmp)
      const x = tmp.x * cosR - tmp.y * sinR + cx
      const z = tmp.x * sinR + tmp.y * cosR + cz
      positions.push(x, s.y, z)
      normals.push(0, 0, 0)
      uvs.push(j / radial, (i / (rings - 1)) * vRepeat)
      points.push(new THREE.Vector3(x, s.y, z))
    }
    ringPoints.push(points)
  }

  for (let i = 0; i < rings - 1; i += 1) {
    for (let j = 0; j < radial; j += 1) {
      const a = i * stride + j
      const b = a + stride
      indices.push(a, b, a + 1, b, b + 1, a + 1)
    }
  }

  const geometry = new THREE.BufferGeometry()
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
  geometry.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3))
  geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2))
  geometry.setIndex(indices)
  geometry.computeVertexNormals()
  averageSeamNormals(geometry, rings, radial)

  if (capStart || capEnd) {
    const pos = Array.from(geometry.attributes.position.array)
    const nor = Array.from(geometry.attributes.normal.array)
    const uv = Array.from(geometry.attributes.uv.array)
    const idx = Array.from(geometry.index.array)
    if (capStart) buildCap(pos, nor, uv, idx, ringPoints[0], true)
    if (capEnd) buildCap(pos, nor, uv, idx, ringPoints[rings - 1], false)

    const capped = new THREE.BufferGeometry()
    capped.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3))
    capped.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3))
    capped.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2))
    capped.setIndex(idx)
    capped.userData.rings = rings
    capped.userData.radial = radial
    return capped
  }

  geometry.userData.rings = rings
  geometry.userData.radial = radial
  return geometry
}

/**
 * Loft along an arbitrary 3D curve — sleeves, trouser legs and straps all hang
 * on a curve so they can droop instead of sticking out rigidly.
 * profile(t) -> { w, d, n?, rot? }
 */
export function loftAlongPath(curve, profile, options = {}) {
  const { steps = 26, radial = 40, capStart = false, capEnd = true } = options
  const frames = curve.computeFrenetFrames(steps, false)
  const sections = []
  const positions = []
  const normals = []
  const uvs = []
  const indices = []
  const stride = radial + 1
  const tmp = new THREE.Vector2()
  const point = new THREE.Vector3()

  for (let i = 0; i <= steps; i += 1) {
    const t = i / steps
    const p = curve.getPointAt(t)
    const N = frames.normals[Math.min(i, steps - 1)]
    const B = frames.binormals[Math.min(i, steps - 1)]
    const shape = profile(t)
    const n = shape.n ?? 2.4
    const rot = shape.rot ?? 0
    const cosR = Math.cos(rot)
    const sinR = Math.sin(rot)
    const ring = []

    for (let j = 0; j <= radial; j += 1) {
      const a = (j / radial) * Math.PI * 2
      sectionPoint(a, shape.w, shape.d, n, tmp)
      const u = tmp.x * cosR - tmp.y * sinR
      const v = tmp.x * sinR + tmp.y * cosR
      point.copy(p).addScaledVector(N, u).addScaledVector(B, v)
      positions.push(point.x, point.y, point.z)
      normals.push(0, 0, 0)
      uvs.push(j / radial, t)
      ring.push(point.clone())
    }
    sections.push(ring)
  }

  for (let i = 0; i < steps; i += 1) {
    for (let j = 0; j < radial; j += 1) {
      const a = i * stride + j
      const b = a + stride
      indices.push(a, b, a + 1, b, b + 1, a + 1)
    }
  }

  const geometry = new THREE.BufferGeometry()
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
  geometry.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3))
  geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2))
  geometry.setIndex(indices)
  geometry.computeVertexNormals()
  averageSeamNormals(geometry, steps + 1, radial)

  if (!capStart && !capEnd) return geometry

  const pos = Array.from(geometry.attributes.position.array)
  const nor = Array.from(geometry.attributes.normal.array)
  const uv = Array.from(geometry.attributes.uv.array)
  const idx = Array.from(geometry.index.array)
  if (capStart) buildCap(pos, nor, uv, idx, sections[0], true)
  if (capEnd) buildCap(pos, nor, uv, idx, sections[steps], false)

  const capped = new THREE.BufferGeometry()
  capped.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3))
  capped.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3))
  capped.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2))
  capped.setIndex(idx)
  return capped
}

/**
 * Push vertices along their normals with layered noise plus vertical folds, so
 * a lofted shell picks up creases, drape and the weight of its fabric.
 */
export function drapeCloth(geometry, options = {}) {
  const {
    amp = 0.012,
    freq = 5.5,
    seed = 1,
    octaves = 3,
    folds = 0,
    foldAmp = 0.01,
    foldFrom = 0,
    foldTo = 1,
    minY = null,
    maxY = null,
  } = options

  const pos = geometry.attributes.position
  const nor = geometry.attributes.normal
  let lo = Infinity
  let hi = -Infinity
  for (let i = 0; i < pos.count; i += 1) {
    const y = pos.getY(i)
    if (y < lo) lo = y
    if (y > hi) hi = y
  }
  const low = minY ?? lo
  const high = maxY ?? hi
  const span = Math.max(1e-5, high - low)

  for (let i = 0; i < pos.count; i += 1) {
    const x = pos.getX(i)
    const y = pos.getY(i)
    const z = pos.getZ(i)
    const h = (y - low) / span

    let offset = fbm3(x * freq, y * freq * 0.85, z * freq, seed, octaves) * amp

    if (folds > 0) {
      const window = THREE.MathUtils.smoothstep(h, foldFrom, foldTo)
      const angle = Math.atan2(z, x)
      offset += Math.sin(angle * folds) * foldAmp * window
    }

    pos.setXYZ(i, x + nor.getX(i) * offset, y + nor.getY(i) * offset, z + nor.getZ(i) * offset)
  }

  pos.needsUpdate = true
  geometry.computeVertexNormals()
  if (geometry.userData.rings) {
    averageSeamNormals(geometry, geometry.userData.rings, geometry.userData.radial)
  }
  return geometry
}

export function curveFrom(points) {
  return new THREE.CatmullRomCurve3(points.map(p => new THREE.Vector3(p[0], p[1], p[2])), false, 'catmullrom', 0.25)
}
