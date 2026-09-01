import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { buildGarment, recolorGarment, disposeGarment } from '../three/garments.js'
import {
  createRenderer, createStudioScene, createCamera, applyPreset, createBackdrop,
  createGrid, applyGridColors, SCENE_PRESETS, hasWebGL,
} from '../three/studio.js'
import { createComposer, setConstructionView, countTriangles } from '../three/effects.js'
import { useReducedMotion } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

// The live viewer. Geometry is rebuilt only when the garment itself changes;
// switching colourway, scene or lighting mutates what is already on screen, so
// the model keeps spinning while you flick through options.
export default function Viewer3D({
  spec,
  label,
  autoRotate = true,
  interactive = true,
  showHud = true,
  showTelemetry = false,
  preset: presetProp = 'studio',
  bloom = true,
  bloomStrength = 0.45,
  grid = true,
  exposure = 1,
  onPresetChange,
  className = '',
}) {
  const canvasRef = useRef(null)
  const stateRef = useRef(null)
  const fpsRef = useRef(null)
  const [ready, setReady] = useState(false)
  const [supported] = useState(() => hasWebGL())
  const [spinning, setSpinning] = useState(autoRotate)
  const [xray, setXray] = useState(false)
  const [preset, setPreset] = useState(presetProp)
  const [tris, setTris] = useState(0)
  const reducedMotion = useReducedMotion()

  const geometryKey = `${spec.kind}|${spec.fit}|${spec.fabric}|${spec.seed}`

  useEffect(() => {
    if (!supported || !canvasRef.current) return undefined
    const canvas = canvasRef.current
    const renderer = createRenderer(canvas, { alpha: false, dpr: Math.min(2, window.devicePixelRatio || 1) })
    const studio = createStudioScene(renderer, preset)
    const camera = createCamera(1)

    studio.scene.background = createBackdrop(preset)
    const gridMesh = createGrid(preset)
    studio.scene.add(gridMesh)
    studio.scene.fog = new THREE.Fog(new THREE.Color(SCENE_PRESETS[preset].backdrop[1]), 6.5, 17)

    const controls = new OrbitControls(camera, canvas)
    controls.enableDamping = true
    controls.dampingFactor = 0.075
    controls.enablePan = false
    controls.enabled = interactive
    controls.minDistance = 2.4
    controls.maxDistance = 7.5
    controls.minPolarAngle = Math.PI * 0.1
    controls.maxPolarAngle = Math.PI * 0.86
    controls.rotateSpeed = 0.85
    controls.zoomSpeed = 0.7

    const { composer, bloom: bloomPass } = createComposer(renderer, studio.scene, camera, { strength: bloomStrength })

    const state = {
      renderer, studio, camera, controls, composer, bloomPass, gridMesh,
      garment: null, dirty: true, spinning: false, useBloom: bloom, frame: 0,
      lastFrame: performance.now(), fpsAccum: 0, fpsCount: 0,
    }
    stateRef.current = state

    controls.addEventListener('change', () => { state.dirty = true })

    const resize = () => {
      const rect = canvas.parentElement.getBoundingClientRect()
      const width = Math.max(1, Math.round(rect.width))
      const height = Math.max(1, Math.round(rect.height))
      renderer.setSize(width, height, false)
      composer.setSize(width, height)
      bloomPass.setSize(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2)))
      camera.aspect = width / height
      camera.updateProjectionMatrix()
      state.dirty = true
    }
    resize()

    const observer = new ResizeObserver(resize)
    observer.observe(canvas.parentElement)

    let visible = true
    const io = new IntersectionObserver(entries => { visible = entries[0]?.isIntersecting ?? true }, { threshold: 0.01 })
    io.observe(canvas)

    const tick = () => {
      state.frame = requestAnimationFrame(tick)
      if (!visible) return
      const now = performance.now()
      const delta = now - state.lastFrame
      state.lastFrame = now

      if (state.spinning && state.garment) {
        state.garment.rotation.y += 0.0042
        state.dirty = true
      }
      state.fpsAccum += delta
      state.fpsCount += 1
      // A per-frame counter has no business in React state — write it straight
      // to the node, so a heavy frame can never stall the update.
      if (state.fpsAccum > 700) {
        if (fpsRef.current) fpsRef.current.textContent = String(Math.max(1, Math.round(1000 / (state.fpsAccum / state.fpsCount))))
        state.fpsAccum = 0
        state.fpsCount = 0
      }

      if (controls.enableDamping) controls.update()
      if (!state.dirty) return
      state.dirty = false

      if (state.useBloom) composer.render()
      else renderer.render(studio.scene, camera)
    }
    state.frame = requestAnimationFrame(tick)

    return () => {
      cancelAnimationFrame(state.frame)
      observer.disconnect()
      io.disconnect()
      controls.dispose()
      if (state.garment) {
        studio.scene.remove(state.garment)
        disposeGarment(state.garment)
      }
      studio.scene.background?.dispose?.()
      gridMesh.geometry.dispose()
      gridMesh.material.dispose()
      composer.dispose?.()
      renderer.dispose()
      stateRef.current = null
    }
    // The scene is created once per mounted viewer; the effects below apply
    // every setting change to the live scene.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supported, interactive])

  // Rebuild geometry only when the garment itself changes.
  useEffect(() => {
    const state = stateRef.current
    if (!state) return
    if (state.garment) {
      state.studio.scene.remove(state.garment)
      disposeGarment(state.garment)
    }
    state.garment = buildGarment(spec)
    state.garment.rotation.y = spec.angle ?? -0.42
    state.studio.scene.add(state.garment)
    recolorGarment(state.garment, { color: spec.color, accent: spec.accent })
    setConstructionView(state.garment, xray)
    setTris(countTriangles(state.garment))
    state.dirty = true
    setReady(true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [geometryKey, supported])

  useEffect(() => {
    const state = stateRef.current
    if (!state?.garment) return
    recolorGarment(state.garment, { color: spec.color, accent: spec.accent })
    setConstructionView(state.garment, xray)
    state.dirty = true
  }, [spec.color, spec.accent, xray])

  useEffect(() => {
    const state = stateRef.current
    if (!state) return
    applyPreset(state.studio, preset)
    state.studio.scene.background?.dispose?.()
    state.studio.scene.background = createBackdrop(preset)
    applyGridColors(state.gridMesh, preset)
    state.studio.scene.fog?.color.set(SCENE_PRESETS[preset].backdrop[1])
    state.renderer.toneMappingExposure = SCENE_PRESETS[preset].exposure * exposure
    state.dirty = true
  }, [preset, exposure])

  useEffect(() => {
    const state = stateRef.current
    if (!state) return
    state.useBloom = bloom
    state.bloomPass.strength = bloomStrength
    state.gridMesh.visible = grid
    state.dirty = true
  }, [bloom, bloomStrength, grid])

  useEffect(() => { setPreset(presetProp) }, [presetProp])

  useEffect(() => {
    const state = stateRef.current
    if (!state) return
    state.spinning = spinning && !reducedMotion
    state.dirty = true
  }, [spinning, reducedMotion, ready])

  const zoom = direction => {
    const state = stateRef.current
    if (!state) return
    const next = THREE.MathUtils.clamp(state.camera.position.length() * (direction > 0 ? 0.85 : 1.18), 2.4, 7.5)
    state.camera.position.setLength(next)
    state.controls.update()
    state.dirty = true
  }

  const reset = () => {
    const state = stateRef.current
    if (!state) return
    state.camera.position.set(0, 0.18, 4.6)
    state.controls.target.set(0, 0, 0)
    state.controls.update()
    if (state.garment) state.garment.rotation.set(0, spec.angle ?? -0.42, 0)
    state.dirty = true
  }

  if (!supported) {
    return (
      <div className={`viewer ${className}`}>
        <div className="viewer__loading" style={{ padding: 24, textAlign: 'center', lineHeight: 1.8 }}>
          3D preview needs WebGL<br />
          <span style={{ color: 'var(--text-2)' }}>{label}</span>
        </div>
      </div>
    )
  }

  return (
    <div className={`viewer ${className}`}>
      <canvas ref={canvasRef} aria-label={`Interactive 3D render of ${label}. Drag to rotate.`} role="img" />
      {!ready && <div className="viewer__loading">Rendering…</div>}

      <div className="viewer__badge">
        <span className="viewer__dot" />
        Live WebGL render
      </div>

      {showTelemetry && ready && (
        <dl className="viewer__telemetry" aria-label="Render telemetry">
          <div><dt>Tris</dt><dd>{tris.toLocaleString()}</dd></div>
          <div><dt>FPS</dt><dd ref={fpsRef}>—</dd></div>
          <div><dt>Shader</dt><dd>Physical</dd></div>
          <div><dt>Mode</dt><dd>{xray ? 'Construction' : 'Shaded'}</dd></div>
        </dl>
      )}

      {showHud && ready && (
        <div className="viewer__hud">
          <button type="button" className="viewer__chip" aria-pressed={spinning} onClick={() => setSpinning(v => !v)}>
            <Icon name="rotate" size={13} />
            {spinning ? 'Spinning' : 'Paused'}
          </button>
          <button type="button" className="viewer__chip" aria-pressed={xray} onClick={() => setXray(v => !v)}>
            <Icon name="layers" size={13} />
            X-ray
          </button>
          <button type="button" className="viewer__chip" onClick={() => zoom(1)} aria-label="Zoom in">
            <Icon name="zoomIn" size={13} />
          </button>
          <button type="button" className="viewer__chip" onClick={() => zoom(-1)} aria-label="Zoom out">
            <Icon name="zoomOut" size={13} />
          </button>
          <button type="button" className="viewer__chip" onClick={reset} aria-label="Reset view">
            <Icon name="reset" size={13} />
          </button>
          <div style={{ flex: 1 }} />
          {Object.entries(SCENE_PRESETS).map(([id, value]) => (
            <button
              key={id} type="button" className="viewer__chip" aria-pressed={preset === id}
              onClick={() => { setPreset(id); onPresetChange?.(id) }}
            >
              {value.label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
