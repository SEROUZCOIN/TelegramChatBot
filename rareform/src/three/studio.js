import * as THREE from 'three'
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js'

// One shared studio setup drives both the interactive viewer and the offscreen
// thumbnail renderer, so a card and its product page are lit identically.

export const SCENE_PRESETS = {
  studio: {
    label: 'Studio',
    key: { color: '#fffaf0', intensity: 3.1, position: [2.6, 3.6, 3.2] },
    fill: { color: '#cfe0ff', intensity: 0.85, position: [-3.4, 1.4, 2.2] },
    rim: { color: '#ffffff', intensity: 2.2, position: [-1.4, 2.4, -3.8] },
    ambient: 0.55,
    exposure: 1.0,
    ground: 0.3,
    backdrop: ['#ffffff', '#d9d5c9'],
    grid: '#b9b4a5',
    gridCore: '#8f8a7c',
  },
  obsidian: {
    label: 'Obsidian',
    key: { color: '#f4ffe0', intensity: 3.4, position: [2.2, 3.2, 2.6] },
    fill: { color: '#2f4a3a', intensity: 0.5, position: [-3.2, 0.8, 2.6] },
    rim: { color: '#ceff25', intensity: 2.6, position: [-1.8, 2.0, -3.4] },
    ambient: 0.22,
    exposure: 1.12,
    ground: 0.5,
    backdrop: ['#1b1f1a', '#050605'],
    grid: '#39402f',
    gridCore: '#6d7a55',
  },
  daylight: {
    label: 'Daylight',
    key: { color: '#ffffff', intensity: 3.6, position: [1.8, 4.2, 2.8] },
    fill: { color: '#dbe8ff', intensity: 1.35, position: [-3.0, 2.0, 2.4] },
    rim: { color: '#ffe9c9', intensity: 1.4, position: [-1.0, 2.6, -3.6] },
    ambient: 0.8,
    exposure: 0.98,
    ground: 0.22,
    backdrop: ['#ffffff', '#c9d6e4'],
    grid: '#a9b6c4',
    gridCore: '#7f8d9c',
  },
  hologram: {
    label: 'Hologram',
    key: { color: '#dcffb0', intensity: 2.4, position: [2.4, 3.4, 2.8] },
    fill: { color: '#4a7f8a', intensity: 1.35, position: [-3.2, 1.0, 2.4] },
    rim: { color: '#ceff25', intensity: 2.7, position: [-1.6, 1.8, -3.2] },
    ambient: 0.2,
    exposure: 1.18,
    ground: 0.42,
    backdrop: ['#141a16', '#050706'],
    grid: '#3f6b3a',
    gridCore: '#ceff25',
  },
  noir: {
    label: 'Noir',
    key: { color: '#ffffff', intensity: 4.2, position: [3.0, 2.6, 1.6] },
    fill: { color: '#5b6470', intensity: 0.22, position: [-3.4, 0.6, 1.8] },
    rim: { color: '#9fb4ff', intensity: 3.0, position: [-2.0, 2.2, -3.0] },
    ambient: 0.12,
    exposure: 1.2,
    ground: 0.62,
    backdrop: ['#1a1c20', '#000000'],
    grid: '#2c3138',
    gridCore: '#59626e',
  },
}

let sharedEnv = null

export function environmentMap(renderer) {
  if (!sharedEnv) {
    const pmrem = new THREE.PMREMGenerator(renderer)
    sharedEnv = pmrem.fromScene(new RoomEnvironment(), 0.04).texture
    pmrem.dispose()
  }
  return sharedEnv
}

export function createRenderer(canvas, { alpha = true, antialias = true, dpr = 1 } = {}) {
  const renderer = new THREE.WebGLRenderer({ canvas, alpha, antialias, preserveDrawingBuffer: true, powerPreference: 'high-performance' })
  renderer.setPixelRatio(dpr)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  return renderer
}

export function createStudioScene(renderer, presetName = 'studio') {
  const preset = SCENE_PRESETS[presetName] ?? SCENE_PRESETS.studio
  const scene = new THREE.Scene()
  scene.environment = environmentMap(renderer)
  scene.environmentIntensity = 0.55

  const ambient = new THREE.AmbientLight('#ffffff', preset.ambient)
  scene.add(ambient)

  const key = new THREE.DirectionalLight(preset.key.color, preset.key.intensity)
  key.position.set(...preset.key.position)
  key.castShadow = true
  key.shadow.mapSize.set(1024, 1024)
  key.shadow.camera.near = 0.5
  key.shadow.camera.far = 14
  key.shadow.camera.left = -2
  key.shadow.camera.right = 2
  key.shadow.camera.top = 2.4
  key.shadow.camera.bottom = -2.4
  key.shadow.bias = -0.0016
  key.shadow.normalBias = 0.02
  key.shadow.radius = 3
  scene.add(key)

  const fill = new THREE.DirectionalLight(preset.fill.color, preset.fill.intensity)
  fill.position.set(...preset.fill.position)
  scene.add(fill)

  const rim = new THREE.DirectionalLight(preset.rim.color, preset.rim.intensity)
  rim.position.set(...preset.rim.position)
  scene.add(rim)

  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(12, 12),
    new THREE.ShadowMaterial({ opacity: preset.ground, color: '#000000' }),
  )
  floor.rotation.x = -Math.PI / 2
  floor.position.y = -0.86
  floor.receiveShadow = true
  scene.add(floor)

  renderer.toneMappingExposure = preset.exposure

  return { scene, lights: { ambient, key, fill, rim }, floor, preset }
}

export function applyPreset(ctx, presetName) {
  const preset = SCENE_PRESETS[presetName] ?? SCENE_PRESETS.studio
  const { lights, floor } = ctx
  lights.ambient.intensity = preset.ambient
  lights.key.color.set(preset.key.color)
  lights.key.intensity = preset.key.intensity
  lights.key.position.set(...preset.key.position)
  lights.fill.color.set(preset.fill.color)
  lights.fill.intensity = preset.fill.intensity
  lights.fill.position.set(...preset.fill.position)
  lights.rim.color.set(preset.rim.color)
  lights.rim.intensity = preset.rim.intensity
  lights.rim.position.set(...preset.rim.position)
  floor.material.opacity = preset.ground
  ctx.preset = preset
  return preset
}

export function createCamera(aspect) {
  const camera = new THREE.PerspectiveCamera(30, aspect, 0.1, 60)
  camera.position.set(0, 0.18, 4.6)
  camera.lookAt(0, 0, 0)
  return camera
}

// A radial backdrop plus a receding grid give the viewer somewhere to sit.
// Thumbnails deliberately skip both so product cards stay transparent.
export function createBackdrop(presetName) {
  const preset = SCENE_PRESETS[presetName] ?? SCENE_PRESETS.studio
  const canvas = document.createElement('canvas')
  canvas.width = 32
  canvas.height = 256
  const ctx = canvas.getContext('2d')
  const gradient = ctx.createLinearGradient(0, 0, 0, 256)
  gradient.addColorStop(0, preset.backdrop[0])
  gradient.addColorStop(1, preset.backdrop[1])
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, 32, 256)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  return texture
}

export function createGrid(presetName) {
  const preset = SCENE_PRESETS[presetName] ?? SCENE_PRESETS.studio
  const grid = new THREE.GridHelper(44, 88, preset.gridCore, preset.grid)
  grid.position.y = -0.861
  grid.material.transparent = true
  grid.material.opacity = 0.5
  grid.material.depthWrite = false
  return grid
}

export function applyGridColors(grid, presetName) {
  const preset = SCENE_PRESETS[presetName] ?? SCENE_PRESETS.studio
  const next = new THREE.GridHelper(44, 88, preset.gridCore, preset.grid)
  grid.geometry.dispose()
  grid.geometry = next.geometry
  next.material.dispose()
}

let webglSupported = null
export function hasWebGL() {
  if (webglSupported !== null) return webglSupported
  try {
    const canvas = document.createElement('canvas')
    webglSupported = Boolean(
      window.WebGLRenderingContext && (canvas.getContext('webgl2') || canvas.getContext('webgl')),
    )
  } catch {
    webglSupported = false
  }
  return webglSupported
}
