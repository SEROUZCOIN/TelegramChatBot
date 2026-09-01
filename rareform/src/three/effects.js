import * as THREE from 'three'
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js'
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js'

// Bloom is only used by the interactive viewer. Cards render straight through
// the renderer so they keep their alpha channel.

export function createComposer(renderer, scene, camera, { strength = 0.45 } = {}) {
  const composer = new EffectComposer(renderer)
  composer.addPass(new RenderPass(scene, camera))

  const size = new THREE.Vector2()
  renderer.getSize(size)
  const bloom = new UnrealBloomPass(size, strength, 0.55, 0.86)
  composer.addPass(bloom)
  composer.addPass(new OutputPass())

  return { composer, bloom }
}

// Construction view: the wireframe reveals how each garment is actually built,
// which is the whole premise of the catalogue.
export function setConstructionView(root, on) {
  root.traverse(node => {
    if (!node.isMesh) return
    const slot = node.userData.slot
    if (slot === 'interior') {
      node.visible = !on
      return
    }
    node.material.wireframe = on
    node.material.transparent = on
    node.material.opacity = on ? 0.62 : 1
    node.material.needsUpdate = true
  })
}

export function countTriangles(root) {
  let total = 0
  root.traverse(node => {
    if (!node.isMesh) return
    const geometry = node.geometry
    total += (geometry.index ? geometry.index.count : geometry.attributes.position.count) / 3
  })
  return Math.round(total)
}
