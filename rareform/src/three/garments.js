import * as THREE from 'three'
import { loftSections, loftAlongPath, drapeCloth, curveFrom } from './loft.js'
import { fabricMaterial, hardwareMaterial, rubberMaterial, FABRICS } from './materials.js'

// Garments are lofted from cross-sections rather than loaded from files. Each
// builder returns a Group whose meshes are tagged with a `slot` so colourways
// can be swapped on a live scene without rebuilding geometry.

const FIT_SCALE = {
  slim: { w: 0.9, l: 1.0 },
  regular: { w: 1.0, l: 1.0 },
  relaxed: { w: 1.07, l: 1.02 },
  oversized: { w: 1.16, l: 1.07 },
  cropped: { w: 1.04, l: 0.82 },
}

function tag(mesh, slot) {
  mesh.userData.slot = slot
  mesh.castShadow = true
  mesh.receiveShadow = true
  return mesh
}

function shell(sections, material, slot, drape, group, radial = 56) {
  const geo = loftSections(sections, { radial })
  if (drape) drapeCloth(geo, drape)
  const mesh = new THREE.Mesh(geo, material)
  group.add(tag(mesh, slot))
  return mesh
}

// A partial cylinder hugs the torso, which makes it the right primitive for
// pockets, plackets, rib bands and waistbands.
function band(radiusX, radiusZ, height, material, slot, group, opts = {}) {
  const { thetaStart = 0, thetaLength = Math.PI * 2, y = 0, z = 0, open = true, segments = 48 } = opts
  const geo = new THREE.CylinderGeometry(1, 1, height, segments, 2, open, thetaStart, thetaLength)
  geo.scale(radiusX, 1, radiusZ)
  const mesh = new THREE.Mesh(geo, material)
  mesh.position.set(0, y, z)
  group.add(tag(mesh, slot))
  return mesh
}

function limb(points, profile, material, slot, group, opts = {}) {
  const geo = loftAlongPath(curveFrom(points), profile, { steps: 24, radial: 34, capEnd: true, ...opts })
  if (opts.drape) drapeCloth(geo, opts.drape)
  const mesh = new THREE.Mesh(geo, material)
  group.add(tag(mesh, slot))
  return mesh
}

function torsoSections({ len, hemW, waistW, chestW, shoulderW, neckW, depth, n = 2.7, hemFlare = 0 }) {
  return [
    { y: 0, w: hemW * (1 + hemFlare), d: hemW * depth * (1 + hemFlare * 0.6), n },
    { y: len * 0.12, w: hemW, d: hemW * depth, n },
    { y: len * 0.34, w: waistW, d: waistW * depth * 1.02, n },
    { y: len * 0.58, w: (waistW + chestW) / 2, d: ((waistW + chestW) / 2) * depth * 1.05, n },
    { y: len * 0.76, w: chestW, d: chestW * depth * 1.06, n },
    { y: len * 0.88, w: shoulderW, d: shoulderW * depth * 0.98, n: n + 0.5 },
    { y: len * 0.945, w: shoulderW * 0.62, d: shoulderW * depth * 0.86, n: n + 0.3 },
    { y: len * 0.99, w: neckW * 1.25, d: neckW * 1.05, n: 2.2 },
    { y: len * 1.02, w: neckW, d: neckW * 0.92, n: 2.1 },
  ]
}

function darkOf(color, amount = 0.62) {
  return new THREE.Color(color).lerp(new THREE.Color('#000000'), amount).getHexString()
}

// A recessed dark disc closes the neck and hem so we read a hollow garment
// instead of a solid tube, without paying for a full inner shell.
function interiorDisc(section, y, material, group, scale = 0.94) {
  const shape = new THREE.Shape()
  const steps = 40
  for (let i = 0; i <= steps; i += 1) {
    const t = (i / steps) * Math.PI * 2
    const c = Math.cos(t)
    const s = Math.sin(t)
    const p = 2 / (section.n ?? 2.6)
    const x = Math.sign(c) * Math.pow(Math.abs(c), p) * section.w * scale
    const z = Math.sign(s) * Math.pow(Math.abs(s), p) * section.d * scale
    if (i === 0) shape.moveTo(x, z)
    else shape.lineTo(x, z)
  }
  const geo = new THREE.ShapeGeometry(shape, 1)
  geo.rotateX(Math.PI / 2)
  const mesh = new THREE.Mesh(geo, material)
  mesh.position.y = y
  mesh.userData.slot = 'interior'
  group.add(mesh)
  return mesh
}

function sleeveCurve(side, shoulderX, shoulderY, length, angle, forward) {
  const reach = Math.cos(angle)
  const fall = Math.sin(angle)
  return [
    [side * shoulderX * 0.72, shoulderY, 0],
    [side * (shoulderX + length * 0.3 * reach), shoulderY - length * 0.24 * fall, forward * 0.25],
    [side * (shoulderX + length * 0.68 * reach), shoulderY - length * 0.66 * fall, forward * 0.7],
    [side * (shoulderX + length * reach), shoulderY - length * fall, forward],
  ]
}

function addSleeves(group, material, fabric, opts) {
  const { shoulderX, shoulderY, length, angle, forward = 0.06, top = 0.135, end = 0.105, cuff = null, seed = 1 } = opts
  for (const side of [-1, 1]) {
    limb(
      sleeveCurve(side, shoulderX, shoulderY, length, angle, forward),
      t => ({ w: THREE.MathUtils.lerp(top, end, t), d: THREE.MathUtils.lerp(top * 0.94, end * 0.94, t), n: 2.3 }),
      material,
      'body',
      group,
      { capEnd: false, drape: { amp: FABRICS[fabric].drape * 0.7, freq: 9, seed: seed + side, folds: 5, foldAmp: 0.004 } },
    )
    if (cuff) {
      const tip = sleeveCurve(side, shoulderX, shoulderY, length, angle, forward).at(-1)
      const c = new THREE.Mesh(new THREE.CylinderGeometry(end * 1.06, end * 1.02, 0.06, 26, 1, true), cuff)
      c.position.set(tip[0], tip[1] + 0.02, tip[2])
      c.rotation.z = side * (Math.PI / 2 - angle)
      group.add(tag(c, 'accent'))
    }
  }
}

function addHood(group, material, fabric, opts) {
  const { neckY, width, depth, seed } = opts
  const path = [
    [0, neckY - 0.05, -depth * 0.15],
    [0, neckY + 0.14, -depth * 0.7],
    [0, neckY + 0.04, -depth * 1.3],
    [0, neckY - 0.32, -depth * 1.45],
  ]
  limb(
    path,
    t => ({ w: width * (1 - 0.2 * t * t), d: width * 0.8 * (1 - 0.14 * t), n: 2.6 }),
    material,
    'body',
    group,
    { steps: 22, radial: 34, capEnd: false, drape: { amp: FABRICS[fabric].drape, freq: 7, seed, folds: 6, foldAmp: 0.006 } },
  )
}

function addPocket(group, material, opts) {
  const { radiusX, radiusZ, y, height, span = 1.5, offset = 1.04 } = opts
  const geo = new THREE.CylinderGeometry(1, 1, height, 40, 2, true, Math.PI / 2 - span / 2, span)
  geo.scale(radiusX * offset, 1, radiusZ * offset)
  const mesh = new THREE.Mesh(geo, material)
  mesh.position.y = y
  group.add(tag(mesh, 'accent'))
  return mesh
}

function addDrawcords(group, material, opts) {
  const { y, x, z } = opts
  for (const side of [-1, 1]) {
    const curve = curveFrom([
      [side * x, y, z],
      [side * x * 1.1, y - 0.09, z * 1.06],
      [side * x * 0.92, y - 0.19, z * 1.02],
    ])
    const mesh = new THREE.Mesh(new THREE.TubeGeometry(curve, 14, 0.009, 8, false), material)
    group.add(tag(mesh, 'trim'))
  }
}

function legs(group, material, fabric, opts) {
  const { crotchY, ankleY, spread, topR, ankleR, seed, flare = 1, taperN = 2.5 } = opts
  for (const side of [-1, 1]) {
    limb(
      [
        [side * spread * 0.62, crotchY + 0.12, 0],
        [side * spread, crotchY - (crotchY - ankleY) * 0.35, 0.01],
        [side * spread * 1.04, crotchY - (crotchY - ankleY) * 0.72, 0.005],
        [side * spread * 1.05, ankleY, 0],
      ],
      t => ({
        w: THREE.MathUtils.lerp(topR, ankleR * flare, t),
        d: THREE.MathUtils.lerp(topR * 1.02, ankleR * flare * 1.04, t),
        n: taperN,
      }),
      material,
      'body',
      group,
      { steps: 26, radial: 36, drape: { amp: FABRICS[fabric].drape, freq: 7.5, seed: seed + side * 3, folds: 7, foldAmp: 0.006 } },
    )
  }
}

/* ------------------------------------------------------------------ */
/* Individual garment builders                                         */
/* ------------------------------------------------------------------ */

function buildTop(spec, variant) {
  const group = new THREE.Group()
  const fit = FIT_SCALE[spec.fit] ?? FIT_SCALE.regular
  const w = fit.w
  const l = fit.l
  const fabric = spec.fabric
  const body = fabricMaterial(spec.color, fabric)
  const accent = fabricMaterial(spec.accent ?? spec.color, fabric === 'silk' ? 'silk' : 'knit')
  const inner = new THREE.MeshStandardMaterial({ color: `#${darkOf(spec.color, 0.7)}`, roughness: 0.95, side: THREE.DoubleSide })

  const base = {
    tee: { len: 1.0, hemW: 0.38, waistW: 0.365, chestW: 0.385, shoulderW: 0.4, neckW: 0.115, depth: 0.46 },
    longsleeve: { len: 1.02, hemW: 0.37, waistW: 0.355, chestW: 0.378, shoulderW: 0.392, neckW: 0.112, depth: 0.46 },
    shirt: { len: 1.06, hemW: 0.375, waistW: 0.355, chestW: 0.375, shoulderW: 0.39, neckW: 0.115, depth: 0.44 },
    sweater: { len: 1.0, hemW: 0.4, waistW: 0.395, chestW: 0.41, shoulderW: 0.425, neckW: 0.125, depth: 0.5 },
    hoodie: { len: 1.04, hemW: 0.43, waistW: 0.425, chestW: 0.44, shoulderW: 0.455, neckW: 0.135, depth: 0.52 },
    jacket: { len: 1.0, hemW: 0.43, waistW: 0.425, chestW: 0.445, shoulderW: 0.46, neckW: 0.135, depth: 0.53 },
    coat: { len: 1.42, hemW: 0.47, waistW: 0.44, chestW: 0.45, shoulderW: 0.465, neckW: 0.135, depth: 0.5 },
  }[variant] ?? { len: 1.0, hemW: 0.38, waistW: 0.37, chestW: 0.39, shoulderW: 0.4, neckW: 0.115, depth: 0.46 }

  const dims = {
    len: base.len * l,
    hemW: base.hemW * w,
    waistW: base.waistW * w,
    chestW: base.chestW * w,
    shoulderW: base.shoulderW * w,
    neckW: base.neckW * Math.min(w, 1.06),
    depth: base.depth,
    hemFlare: variant === 'coat' ? 0.16 : 0,
  }

  const sections = torsoSections(dims)
  shell(sections, body, 'body', {
    amp: FABRICS[fabric].drape,
    freq: 6,
    seed: spec.seed,
    folds: variant === 'coat' ? 9 : 7,
    foldAmp: FABRICS[fabric].drape * 0.7,
    foldFrom: 0.0,
    foldTo: 0.65,
  }, group)

  interiorDisc(sections.at(-1), dims.len * 1.0, inner, group, 0.9)
  interiorDisc(sections[0], 0.012, inner, group, 0.95)

  const shoulderY = dims.len * 0.855
  const sleeveLength = { tee: 0.2, longsleeve: 0.46, shirt: 0.44, sweater: 0.46, hoodie: 0.48, jacket: 0.47, coat: 0.5 }[variant] ?? 0.2
  const short = variant === 'tee'
  addSleeves(group, body, fabric, {
    shoulderX: dims.shoulderW,
    shoulderY,
    length: sleeveLength * (variant === 'coat' ? 1.05 : 1),
    angle: short ? 0.52 : 1.16,
    forward: 0.05,
    top: dims.shoulderW * 0.34,
    end: dims.shoulderW * (short ? 0.31 : 0.24),
    cuff: ['sweater', 'hoodie', 'jacket'].includes(variant) ? accent : null,
    seed: spec.seed,
  })

  const rx = dims.hemW
  const rz = dims.hemW * dims.depth

  if (variant === 'hoodie' || variant === 'sweater' || variant === 'jacket') {
    band(rx * 1.005, rz * 1.005, 0.075, accent, 'accent', group, { y: 0.037 })
  }

  if (variant === 'hoodie') {
    addHood(group, body, fabric, { neckY: dims.len * 0.94, width: dims.neckW * 1.9, depth: 0.3, seed: spec.seed })
    addPocket(group, body, { radiusX: dims.waistW, radiusZ: dims.waistW * dims.depth, y: dims.len * 0.24, height: 0.17, span: 1.25, offset: 1.035 })
    addDrawcords(group, hardwareMaterial('#e6e2d6'), { y: dims.len * 0.9, x: dims.neckW * 0.5, z: dims.neckW * 0.95 })
  }

  if (variant === 'shirt') {
    // Placket plus a run of buttons down the centre front.
    band(dims.chestW * 1.012, dims.chestW * dims.depth * 1.05, dims.len * 0.92, accent, 'accent', group, {
      y: dims.len * 0.5, thetaStart: Math.PI / 2 - 0.16, thetaLength: 0.32,
    })
    const btn = hardwareMaterial('#d9d5c8')
    for (let i = 0; i < 6; i += 1) {
      const b = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.014, 0.008, 16), btn)
      b.rotation.x = Math.PI / 2
      b.position.set(0, dims.len * (0.16 + i * 0.135), dims.chestW * dims.depth * 1.09)
      group.add(tag(b, 'hardware'))
    }
    const collar = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 0.09, 36, 1, true, Math.PI * 0.18, Math.PI * 1.64), accent)
    collar.geometry.scale(dims.neckW * 1.5, 1, dims.neckW * 1.35)
    collar.position.y = dims.len * 0.975
    collar.rotation.x = -0.12
    group.add(tag(collar, 'accent'))
  }

  if (variant === 'jacket' || variant === 'coat') {
    const zipper = new THREE.Mesh(new THREE.BoxGeometry(0.022, dims.len * 0.9, 0.014), hardwareMaterial('#b9bdb4'))
    zipper.position.set(0, dims.len * 0.48, dims.chestW * dims.depth * 1.03)
    group.add(tag(zipper, 'hardware'))
    const pull = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.05, 0.012), hardwareMaterial('#cfd3c9'))
    pull.position.set(0, dims.len * 0.2, dims.chestW * dims.depth * 1.05)
    group.add(tag(pull, 'hardware'))
    const collar = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 0.11, 36, 1, true, Math.PI * 0.12, Math.PI * 1.76), accent)
    collar.geometry.scale(dims.neckW * 1.45, 1, dims.neckW * 1.3)
    collar.position.y = dims.len * 0.985
    group.add(tag(collar, 'accent'))
    for (const side of [-1, 1]) {
      addPocket(group, body, {
        radiusX: dims.waistW, radiusZ: dims.waistW * dims.depth,
        y: dims.len * (variant === 'coat' ? 0.4 : 0.26), height: 0.16, span: 0.5, offset: 1.045,
      }).rotation.y = side * 0.62
    }
  }

  if (variant === 'coat') {
    const belt = band(dims.waistW * 1.03, dims.waistW * dims.depth * 1.05, 0.06, accent, 'accent', group, { y: dims.len * 0.52 })
    belt.userData.slot = 'accent'
  }

  return group
}

function buildBottom(spec, variant) {
  const group = new THREE.Group()
  const fit = FIT_SCALE[spec.fit] ?? FIT_SCALE.regular
  const fabric = spec.fabric
  const body = fabricMaterial(spec.color, fabric)
  const accent = fabricMaterial(spec.accent ?? spec.color, fabric)
  const inner = new THREE.MeshStandardMaterial({ color: `#${darkOf(spec.color, 0.7)}`, roughness: 0.95, side: THREE.DoubleSide })

  const short = variant === 'shorts'
  const top = 1.0
  const crotchY = 0.72
  const ankleY = short ? 0.46 : 0.0
  const w = fit.w

  const hips = [
    { y: crotchY, w: 0.278 * w, d: 0.172 * w, n: 2.7 },
    { y: crotchY + (top - crotchY) * 0.4, w: 0.3 * w, d: 0.183 * w, n: 2.6 },
    { y: crotchY + (top - crotchY) * 0.75, w: 0.29 * w, d: 0.177 * w, n: 2.6 },
    { y: top, w: 0.268 * w, d: 0.163 * w, n: 2.5 },
  ]
  shell(hips, body, 'body', { amp: FABRICS[fabric].drape * 0.8, freq: 7, seed: spec.seed }, group, 48)
  interiorDisc(hips.at(-1), top - 0.008, inner, group, 0.94)

  legs(group, body, fabric, {
    crotchY,
    ankleY,
    spread: 0.138 * w,
    topR: 0.142 * w,
    ankleR: (variant === 'jeans' ? 0.098 : short ? 0.142 : 0.112) * w,
    flare: spec.fit === 'relaxed' || spec.fit === 'oversized' ? 1.18 : 1,
    seed: spec.seed,
  })

  band(0.271 * w, 0.166 * w, 0.058, accent, 'accent', group, { y: top - 0.029 })

  if (variant === 'jeans' || variant === 'pants') {
    const btn = hardwareMaterial('#c2a55f')
    const b = new THREE.Mesh(new THREE.CylinderGeometry(0.017, 0.017, 0.009, 16), btn)
    b.rotation.x = Math.PI / 2
    b.position.set(0, top - 0.03, 0.169 * w)
    group.add(tag(b, 'hardware'))
    const fly = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.14, 0.01), fabricMaterial(`#${darkOf(spec.color, 0.25)}`, fabric))
    fly.position.set(0.006, top - 0.1, 0.168 * w)
    group.add(tag(fly, 'trim'))
    for (const side of [-1, 1]) {
      const pocket = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 0.13, 30, 1, true, -0.45, 0.9), fabricMaterial(`#${darkOf(spec.color, 0.18)}`, fabric))
      pocket.geometry.scale(0.292 * w, 1, 0.18 * w)
      pocket.position.y = top - 0.1
      pocket.rotation.y = Math.PI + side * 0.55
      group.add(tag(pocket, 'trim'))
    }
  }

  return group
}

function buildDress(spec, variant) {
  const group = new THREE.Group()
  const fabric = spec.fabric
  const body = fabricMaterial(spec.color, fabric)
  const inner = new THREE.MeshStandardMaterial({ color: `#${darkOf(spec.color, 0.7)}`, roughness: 0.95, side: THREE.DoubleSide })
  const skirtOnly = variant === 'skirt'
  const len = skirtOnly ? 0.72 : 1.35
  const waistY = skirtOnly ? len : len * 0.6
  const fit = FIT_SCALE[spec.fit] ?? FIT_SCALE.regular

  const sections = []
  const flareByFit = { slim: 0.3, regular: 0.36, relaxed: 0.44, oversized: 0.5, cropped: 0.38 }
  const hemW = (flareByFit[spec.fit] ?? 0.36) * (skirtOnly ? 0.94 : 1)
  const waistW = 0.215 * fit.w

  const skirtSteps = 7
  for (let i = 0; i <= skirtSteps; i += 1) {
    const t = i / skirtSteps
    const y = t * waistY
    const taper = Math.pow(1 - t, 1.35)
    sections.push({
      y,
      w: THREE.MathUtils.lerp(waistW, hemW, taper),
      d: THREE.MathUtils.lerp(waistW * 0.66, hemW * 0.72, taper),
      n: 2.3,
    })
  }

  if (!skirtOnly) {
    sections.push(
      { y: len * 0.72, w: 0.245 * fit.w, d: 0.16 * fit.w, n: 2.5 },
      { y: len * 0.85, w: 0.27 * fit.w, d: 0.175 * fit.w, n: 2.6 },
      { y: len * 0.93, w: 0.28 * fit.w, d: 0.168 * fit.w, n: 2.8 },
      { y: len * 0.975, w: 0.17 * fit.w, d: 0.13 * fit.w, n: 2.4 },
      { y: len, w: 0.1 * fit.w, d: 0.085 * fit.w, n: 2.2 },
    )
  }

  shell(sections, body, 'body', {
    amp: FABRICS[fabric].drape,
    freq: 5,
    seed: spec.seed,
    folds: 6,
    foldAmp: FABRICS[fabric].drape * 0.55,
    foldFrom: 0.0,
    foldTo: 0.6,
  }, group, 64)

  interiorDisc(sections[0], 0.014, inner, group, 0.95)
  interiorDisc(sections.at(-1), sections.at(-1).y - 0.01, inner, group, 0.9)

  if (skirtOnly) {
    band(waistW * 1.01, waistW * 0.67, 0.06, fabricMaterial(spec.accent ?? spec.color, fabric), 'accent', group, { y: waistY - 0.03 })
  } else {
    for (const side of [-1, 1]) {
      const strap = new THREE.Mesh(new THREE.TorusGeometry(0.055, 0.011, 8, 20, Math.PI * 0.9), body)
      strap.position.set(side * 0.14, len * 0.95, 0)
      strap.rotation.set(0, side * 0.4, 0)
      group.add(tag(strap, 'body'))
    }
  }

  return group
}

function buildCap(spec) {
  const group = new THREE.Group()
  const body = fabricMaterial(spec.color, spec.fabric === 'silk' ? 'canvas' : spec.fabric)
  const accent = fabricMaterial(spec.accent ?? spec.color, 'canvas')

  const crown = new THREE.SphereGeometry(0.3, 48, 24, 0, Math.PI * 2, 0, Math.PI * 0.52)
  crown.scale(1, 0.82, 0.94)
  drapeCloth(crown, { amp: 0.004, freq: 12, seed: spec.seed })
  const crownMesh = new THREE.Mesh(crown, body)
  group.add(tag(crownMesh, 'body'))

  const brim = new THREE.CylinderGeometry(0.44, 0.44, 0.022, 40, 3, false, Math.PI * 0.18, Math.PI * 0.64)
  brim.scale(1, 1, 1.05)
  const pos = brim.attributes.position
  for (let i = 0; i < pos.count; i += 1) {
    const x = pos.getX(i)
    const z = pos.getZ(i)
    pos.setY(i, pos.getY(i) - Math.pow(Math.max(0, z) / 0.44, 2) * 0.075 - Math.pow(x / 0.44, 2) * 0.02)
  }
  brim.computeVertexNormals()
  const brimMesh = new THREE.Mesh(brim, accent)
  brimMesh.position.y = 0.012
  group.add(tag(brimMesh, 'accent'))

  const button = new THREE.Mesh(new THREE.SphereGeometry(0.022, 16, 12), accent)
  button.position.y = 0.243
  group.add(tag(button, 'accent'))

  const eyelet = hardwareMaterial('#b7bbb2')
  for (let i = 0; i < 4; i += 1) {
    const e = new THREE.Mesh(new THREE.TorusGeometry(0.011, 0.004, 6, 14), eyelet)
    const a = Math.PI * 0.35 + i * Math.PI * 0.43
    e.position.set(Math.cos(a) * 0.26, 0.13, Math.sin(a) * 0.24)
    e.lookAt(new THREE.Vector3(Math.cos(a) * 2, 0.13, Math.sin(a) * 2))
    group.add(tag(e, 'hardware'))
  }
  return group
}

function buildBeanie(spec) {
  const group = new THREE.Group()
  const body = fabricMaterial(spec.color, spec.fabric === 'cotton' ? 'knit' : spec.fabric)
  const dome = new THREE.SphereGeometry(0.29, 48, 26, 0, Math.PI * 2, 0, Math.PI * 0.62)
  dome.scale(1, 1.06, 1)
  drapeCloth(dome, { amp: 0.009, freq: 14, seed: spec.seed, folds: 10, foldAmp: 0.006 })
  group.add(tag(new THREE.Mesh(dome, body), 'body'))

  const cuff = new THREE.Mesh(new THREE.CylinderGeometry(0.302, 0.296, 0.13, 48, 2, true), fabricMaterial(spec.accent ?? spec.color, 'knit'))
  cuff.position.y = -0.055
  group.add(tag(cuff, 'accent'))

  if (spec.pom !== false) {
    const pom = new THREE.Mesh(new THREE.SphereGeometry(0.08, 20, 16), fabricMaterial(spec.accent ?? spec.color, 'fleece'))
    pom.position.y = 0.31
    group.add(tag(pom, 'accent'))
  }
  return group
}

function buildSneaker(spec) {
  const group = new THREE.Group()
  const upperMat = fabricMaterial(spec.color, spec.fabric === 'cotton' ? 'canvas' : spec.fabric)
  const accent = fabricMaterial(spec.accent ?? '#e8e4d8', 'suede')

  // Footprint, shared by the outsole and midsole so the stack lines up.
  const foot = new THREE.Shape()
  foot.moveTo(-0.36, -0.085)
  foot.bezierCurveTo(-0.42, 0.0, -0.34, 0.105, -0.08, 0.108)
  foot.bezierCurveTo(0.18, 0.112, 0.4, 0.09, 0.45, 0.02)
  foot.bezierCurveTo(0.49, -0.04, 0.4, -0.12, 0.12, -0.125)
  foot.bezierCurveTo(-0.16, -0.13, -0.33, -0.13, -0.36, -0.085)

  const outsole = new THREE.ExtrudeGeometry(foot, {
    depth: 0.03, bevelEnabled: true, bevelSize: 0.012, bevelThickness: 0.01, bevelSegments: 3, curveSegments: 24,
  })
  outsole.rotateX(-Math.PI / 2)
  group.add(tag(new THREE.Mesh(outsole, rubberMaterial(spec.outsoleColor ?? '#1c1e1b')), 'sole'))

  const midsole = new THREE.ExtrudeGeometry(foot, {
    depth: 0.055, bevelEnabled: true, bevelSize: 0.018, bevelThickness: 0.014, bevelSegments: 4, curveSegments: 24,
  })
  midsole.rotateX(-Math.PI / 2)
  midsole.translate(0, 0.028, 0)
  group.add(tag(new THREE.Mesh(midsole, rubberMaterial(spec.soleColor ?? '#efeade')), 'sole'))

  // The upper is lofted heel-to-toe, then rotated so the stacking axis runs
  // along the foot. Each section is offset by its own half-height so the
  // underside stays flat against the midsole.
  const profile = [
    [0.00, 0.112, 0.068, 3.0],
    [0.07, 0.150, 0.086, 2.9],
    [0.20, 0.142, 0.097, 2.9],
    [0.36, 0.118, 0.101, 3.0],
    [0.52, 0.096, 0.099, 3.0],
    [0.66, 0.070, 0.088, 3.1],
    [0.77, 0.049, 0.068, 3.2],
    [0.83, 0.031, 0.043, 3.2],
  ]
  const upperGeo = loftSections(
    profile.map(([y, w, d, n]) => ({ y, w, d, n, cx: -w })),
    { radial: 44, capStart: true, capEnd: true },
  )
  drapeCloth(upperGeo, { amp: 0.0035, freq: 18, seed: spec.seed })
  upperGeo.rotateZ(-Math.PI / 2)
  upperGeo.translate(-0.355, 0.072, 0)
  group.add(tag(new THREE.Mesh(upperGeo, upperMat), 'body'))

  // Heel counter, collar, tongue and laces.
  const counter = new THREE.Mesh(
    new THREE.CylinderGeometry(1, 1, 0.21, 30, 1, true, Math.PI * 0.42, Math.PI * 1.16),
    accent,
  )
  counter.geometry.scale(0.106, 1, 0.098)
  counter.position.set(-0.285, 0.235, 0)
  group.add(tag(counter, 'accent'))

  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.082, 0.017, 10, 28), accent)
  collar.rotation.x = Math.PI / 2
  collar.rotation.z = 0.16
  collar.position.set(-0.205, 0.362, 0)
  collar.scale.set(1.05, 1.25, 1)
  group.add(tag(collar, 'accent'))

  const tongue = new THREE.Mesh(new THREE.BoxGeometry(0.19, 0.026, 0.115), upperMat)
  tongue.position.set(-0.03, 0.328, 0)
  tongue.rotation.z = 0.18
  group.add(tag(tongue, 'body'))

  const laceMat = new THREE.MeshStandardMaterial({ color: '#f2eee2', roughness: 0.88 })
  for (let i = 0; i < 4; i += 1) {
    const x = -0.09 + i * 0.082
    const lift = 0.342 - i * 0.028
    const c = curveFrom([[x, lift, -0.072], [x + 0.028, lift + 0.02, 0], [x, lift, 0.072]])
    group.add(tag(new THREE.Mesh(new THREE.TubeGeometry(c, 14, 0.0075, 7, false), laceMat), 'trim'))
  }

  // Toe cap and a side panel to break up the upper.
  const toe = new THREE.Mesh(new THREE.SphereGeometry(0.062, 22, 16), accent)
  toe.scale.set(1.15, 0.85, 1.35)
  toe.position.set(0.355, 0.125, 0)
  group.add(tag(toe, 'accent'))

  for (const side of [-1, 1]) {
    const panel = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 0.095, 26, 1, true, -0.5, 1.0), accent)
    panel.geometry.scale(0.14, 1, 0.104)
    panel.position.set(0.0, 0.195, 0)
    panel.rotation.set(0, side > 0 ? Math.PI / 2 : -Math.PI / 2, 0)
    panel.scale.set(1, 1, 1)
    group.add(tag(panel, 'accent'))
  }

  return group
}

function buildTote(spec) {
  const group = new THREE.Group()
  const body = fabricMaterial(spec.color, spec.fabric === 'cotton' ? 'canvas' : spec.fabric)
  const sections = [
    { y: 0, w: 0.3, d: 0.09, n: 4.2 },
    { y: 0.1, w: 0.32, d: 0.105, n: 4 },
    { y: 0.4, w: 0.335, d: 0.115, n: 3.6 },
    { y: 0.62, w: 0.325, d: 0.1, n: 3.8 },
  ]
  shell(sections, body, 'body', { amp: 0.012, freq: 6, seed: spec.seed, folds: 8, foldAmp: 0.008 }, group, 52)
  interiorDisc(sections.at(-1), 0.6, new THREE.MeshStandardMaterial({ color: `#${darkOf(spec.color, 0.75)}`, roughness: 0.95, side: THREE.DoubleSide }), group, 0.93)

  const strapMat = fabricMaterial(spec.accent ?? spec.color, 'canvas')
  for (const side of [-1, 1]) {
    const c = curveFrom([
      [side * 0.15, 0.6, 0.06],
      [side * 0.16, 0.82, 0.02],
      [side * 0.15, 0.6, -0.06],
    ])
    const g = new THREE.TubeGeometry(c, 22, 0.016, 8, false)
    g.scale(1, 1, 1)
    group.add(tag(new THREE.Mesh(g, strapMat), 'accent'))
  }
  return group
}

function buildScarf(spec) {
  const group = new THREE.Group()
  const body = fabricMaterial(spec.color, spec.fabric === 'cotton' ? 'wool' : spec.fabric)
  const geo = loftAlongPath(
    curveFrom([
      [-0.02, 1.0, -0.12],
      [-0.2, 0.94, 0.02],
      [-0.14, 0.62, 0.14],
      [0.02, 0.3, 0.1],
      [0.06, 0.0, 0.04],
    ]),
    t => ({ w: 0.115 + Math.sin(t * Math.PI) * 0.02, d: 0.016, n: 5 }),
    { steps: 40, radial: 22, capStart: true, capEnd: true },
  )
  drapeCloth(geo, { amp: 0.012, freq: 9, seed: spec.seed, folds: 6, foldAmp: 0.008 })
  group.add(tag(new THREE.Mesh(geo, body), 'body'))

  const geo2 = loftAlongPath(
    curveFrom([
      [0.02, 1.0, -0.1],
      [0.2, 0.9, 0.04],
      [0.16, 0.55, 0.1],
      [0.1, 0.22, 0.06],
    ]),
    t => ({ w: 0.11, d: 0.015, n: 5 }),
    { steps: 32, radial: 22, capStart: true, capEnd: true },
  )
  drapeCloth(geo2, { amp: 0.012, freq: 9, seed: spec.seed + 4, folds: 6, foldAmp: 0.008 })
  group.add(tag(new THREE.Mesh(geo2, body), 'body'))
  return group
}

const BUILDERS = {
  tee: s => buildTop(s, 'tee'),
  longsleeve: s => buildTop(s, 'longsleeve'),
  shirt: s => buildTop(s, 'shirt'),
  sweater: s => buildTop(s, 'sweater'),
  hoodie: s => buildTop(s, 'hoodie'),
  jacket: s => buildTop(s, 'jacket'),
  coat: s => buildTop(s, 'coat'),
  pants: s => buildBottom(s, 'pants'),
  jeans: s => buildBottom(s, 'jeans'),
  shorts: s => buildBottom(s, 'shorts'),
  dress: s => buildDress(s, 'dress'),
  skirt: s => buildDress(s, 'skirt'),
  cap: buildCap,
  beanie: buildBeanie,
  sneaker: buildSneaker,
  tote: buildTote,
  scarf: buildScarf,
}

export const GARMENT_KINDS = Object.keys(BUILDERS)

/**
 * Build a garment and centre it on the origin with a consistent height, so any
 * product can drop into the same camera framing.
 */
export function buildGarment(spec) {
  const builder = BUILDERS[spec.kind] ?? BUILDERS.tee
  const group = builder({ seed: 1, fabric: 'cotton', fit: 'regular', ...spec })

  const box = new THREE.Box3().setFromObject(group)
  const size = new THREE.Vector3()
  const center = new THREE.Vector3()
  box.getSize(size)
  box.getCenter(center)

  const wrapper = new THREE.Group()
  const scale = 1.5 / Math.max(size.x, size.y, size.z)
  group.position.sub(center)
  group.scale.setScalar(scale)
  group.position.multiplyScalar(scale)
  wrapper.add(group)
  wrapper.userData.radius = (Math.max(size.x, size.y, size.z) * scale) / 2
  return wrapper
}

export function recolorGarment(root, { color, accent }) {
  root.traverse(node => {
    if (!node.isMesh) return
    const slot = node.userData.slot
    if (slot === 'body' && color) node.material.color.set(color)
    if (slot === 'accent' && (accent || color)) node.material.color.set(accent ?? color)
    if (slot === 'interior' && color) {
      node.material.color.set(`#${darkOf(color, 0.7)}`)
    }
    if (slot === 'body' || slot === 'accent') {
      node.material.sheenColor.copy(node.material.color).lerp(new THREE.Color('#ffffff'), 0.6)
    }
  })
}

export function disposeGarment(root) {
  root.traverse(node => {
    if (!node.isMesh) return
    node.geometry.dispose()
    const mats = Array.isArray(node.material) ? node.material : [node.material]
    for (const m of mats) {
      for (const key of ['map', 'normalMap', 'roughnessMap']) m[key]?.dispose?.()
      m.dispose()
    }
  })
}
