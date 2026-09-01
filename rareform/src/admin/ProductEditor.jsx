import { useEffect, useState } from 'react'
import Viewer3D from '../components/Viewer3D.jsx'
import { CATEGORIES, SIZE_SETS, COLOR_FAMILIES } from '../data/catalog.js'
import { GARMENT_KINDS } from '../three/garments.js'
import { FABRICS } from '../three/materials.js'
import { useShop } from '../store/ShopContext.jsx'
import { Icon } from '../lib/icons.jsx'

const FITS = ['slim', 'regular', 'relaxed', 'oversized', 'cropped']
const DEPARTMENTS = ['Women', 'Men', 'Unisex']

function blankProduct(id) {
  return {
    id,
    sku: `RF-NEW-${id.slice(-3)}`,
    name: '',
    category: 'tshirts',
    categoryLabel: 'T-Shirts',
    group: 'Tops',
    department: 'Unisex',
    kind: 'tee',
    fit: 'regular',
    fabric: 'cotton',
    materialLabel: '',
    price: 0,
    compareAt: null,
    colorways: [{ name: 'Ink', hex: '#191b1c', family: 'black', accent: '#191b1c' }],
    sizes: SIZE_SETS.apparel,
    sizeType: 'apparel',
    stock: 0,
    rating: 4.5,
    reviews: 0,
    popularity: 50,
    releasedAt: new Date().toISOString().slice(0, 10),
    description: '',
    details: [],
    care: 'Cold machine wash, dry flat.',
    tags: [],
    badge: null,
    sustainable: false,
    seed: Math.floor(Math.random() * 900) + 11,
  }
}

// The editor renders the garment it is describing, live. Changing kind, fit,
// fabric or a colourway hex rebuilds or recolours the model as you type.
export default function ProductEditor({ productId, onDone }) {
  const { products, upsertProduct, removeProduct, studio } = useShop()
  const existing = products.find(p => p.id === productId)
  const [draft, setDraft] = useState(() => existing ?? blankProduct(`rf-${Date.now().toString().slice(-6)}`))
  const [colorIndex, setColorIndex] = useState(0)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (existing) setDraft(existing)
  }, [existing])

  const set = (key, value) => setDraft(current => ({ ...current, [key]: value }))

  const setCategory = id => {
    const category = CATEGORIES.find(c => c.id === id)
    setDraft(current => ({
      ...current,
      category: id,
      categoryLabel: category.label,
      group: category.group,
      kind: category.kind,
    }))
  }

  const setColorway = (index, patch) => setDraft(current => {
    const colorways = current.colorways.map((cw, i) => (i === index ? { ...cw, ...patch } : cw))
    return { ...current, colorways }
  })

  const addColorway = () => setDraft(current => ({
    ...current,
    colorways: [...current.colorways, { name: `Colour ${current.colorways.length + 1}`, hex: '#8a8f88', family: 'grey', accent: '#8a8f88' }],
  }))

  const removeColorway = index => setDraft(current => (
    current.colorways.length <= 1
      ? current
      : { ...current, colorways: current.colorways.filter((_, i) => i !== index) }
  ))

  const save = () => {
    if (!draft.name.trim()) {
      setError('Give the garment a name.')
      return
    }
    if (!(draft.price > 0)) {
      setError('Set a price above zero.')
      return
    }
    setError(null)
    upsertProduct({
      ...draft,
      price: Number(draft.price),
      compareAt: draft.compareAt ? Number(draft.compareAt) : null,
      stock: Number(draft.stock),
      sizes: SIZE_SETS[draft.sizeType],
      details: typeof draft.details === 'string' ? draft.details.split('\n').filter(Boolean) : draft.details,
      tags: typeof draft.tags === 'string' ? draft.tags.split(',').map(t => t.trim()).filter(Boolean) : draft.tags,
    })
    onDone()
  }

  const colorway = draft.colorways[Math.min(colorIndex, draft.colorways.length - 1)]

  return (
    <div className="editor">
      <div style={{ display: 'grid', gap: 18 }}>
        <div className="editor__grid">
          <div className="field field--wide">
            <label htmlFor="pe-name">Name</label>
            <input id="pe-name" value={draft.name} onChange={e => set('name', e.target.value)} placeholder="Monolith Hoodie" />
          </div>

          <div className="field">
            <label htmlFor="pe-cat">Category</label>
            <select id="pe-cat" value={draft.category} onChange={e => setCategory(e.target.value)}>
              {CATEGORIES.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
            </select>
          </div>

          <div className="field">
            <label htmlFor="pe-kind">3D model</label>
            <select id="pe-kind" value={draft.kind} onChange={e => set('kind', e.target.value)}>
              {GARMENT_KINDS.map(k => <option key={k} value={k}>{k}</option>)}
            </select>
            <span className="field__hint">Drives the geometry that gets built.</span>
          </div>

          <div className="field">
            <label htmlFor="pe-dept">Department</label>
            <select id="pe-dept" value={draft.department} onChange={e => set('department', e.target.value)}>
              {DEPARTMENTS.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>

          <div className="field">
            <label htmlFor="pe-fit">Fit</label>
            <select id="pe-fit" value={draft.fit} onChange={e => set('fit', e.target.value)}>
              {FITS.map(f => <option key={f} value={f}>{f}</option>)}
            </select>
          </div>

          <div className="field">
            <label htmlFor="pe-fabric">Fabric</label>
            <select id="pe-fabric" value={draft.fabric} onChange={e => set('fabric', e.target.value)}>
              {Object.keys(FABRICS).map(f => <option key={f} value={f}>{f}</option>)}
            </select>
            <span className="field__hint">Sets sheen, roughness and how it drapes.</span>
          </div>

          <div className="field">
            <label htmlFor="pe-sizes">Size system</label>
            <select id="pe-sizes" value={draft.sizeType} onChange={e => set('sizeType', e.target.value)}>
              <option value="apparel">Apparel (XXS–XXL)</option>
              <option value="waist">Waist (26–38)</option>
              <option value="shoe">Shoe (UK5–UK11)</option>
              <option value="one">One size</option>
            </select>
          </div>

          <div className="field">
            <label htmlFor="pe-price">Price</label>
            <input id="pe-price" type="number" min="0" value={draft.price} onChange={e => set('price', e.target.value)} />
          </div>

          <div className="field">
            <label htmlFor="pe-was">Compare at</label>
            <input
              id="pe-was" type="number" min="0" value={draft.compareAt ?? ''}
              onChange={e => set('compareAt', e.target.value === '' ? null : e.target.value)} placeholder="—"
            />
          </div>

          <div className="field">
            <label htmlFor="pe-stock">Stock</label>
            <input id="pe-stock" type="number" min="0" value={draft.stock} onChange={e => set('stock', e.target.value)} />
          </div>

          <div className="field">
            <label htmlFor="pe-badge">Badge</label>
            <input id="pe-badge" value={draft.badge ?? ''} onChange={e => set('badge', e.target.value || null)} placeholder="Bestseller" />
          </div>

          <div className="field field--wide">
            <label htmlFor="pe-material">Fabric label</label>
            <input id="pe-material" value={draft.materialLabel} onChange={e => set('materialLabel', e.target.value)} placeholder="480gsm brushed loopback" />
          </div>

          <div className="field field--wide">
            <label htmlFor="pe-desc">Description</label>
            <textarea id="pe-desc" rows={3} value={draft.description} onChange={e => set('description', e.target.value)} />
          </div>

          <div className="field field--wide">
            <label htmlFor="pe-details">Construction notes — one per line</label>
            <textarea
              id="pe-details" rows={3}
              value={Array.isArray(draft.details) ? draft.details.join('\n') : draft.details}
              onChange={e => set('details', e.target.value)}
            />
          </div>

          <div className="field field--wide">
            <label htmlFor="pe-tags">Search tags — comma separated</label>
            <input
              id="pe-tags"
              value={Array.isArray(draft.tags) ? draft.tags.join(', ') : draft.tags}
              onChange={e => set('tags', e.target.value)}
            />
          </div>
        </div>

        <div>
          <div className="pdp__label">
            <span>Colourways</span>
            <button type="button" onClick={addColorway}>Add colourway</button>
          </div>
          <div className="swatches">
            {draft.colorways.map((cw, index) => (
              <div className="swatchedit" key={index}>
                <input
                  type="color" value={cw.hex} aria-label={`Colour ${index + 1} hex`}
                  onChange={e => setColorway(index, { hex: e.target.value, accent: e.target.value })}
                  onFocus={() => setColorIndex(index)}
                />
                <input
                  type="text" value={cw.name} aria-label={`Colour ${index + 1} name`}
                  onChange={e => setColorway(index, { name: e.target.value })}
                  onFocus={() => setColorIndex(index)}
                />
                <select
                  aria-label={`Colour ${index + 1} family`} value={cw.family}
                  onChange={e => setColorway(index, { family: e.target.value })}
                  style={{ height: 26, minHeight: 0, padding: '0 6px', fontSize: 11.5, border: 0, background: 'none' }}
                >
                  {COLOR_FAMILIES.map(f => <option key={f.id} value={f.id}>{f.label}</option>)}
                </select>
                <button type="button" onClick={() => removeColorway(index)} aria-label={`Remove colour ${cw.name}`}>
                  <Icon name="x" size={13} />
                </button>
              </div>
            ))}
          </div>
        </div>

        <label className="toggle">
          <input type="checkbox" checked={draft.sustainable} onChange={e => set('sustainable', e.target.checked)} />
          <span className="toggle__track" />
          <span>Made with responsibly sourced materials</span>
        </label>

        {error && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13 }}>{error}</p>}

        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button type="button" className="btn btn--primary" onClick={save}>
            {existing ? 'Save changes' : 'Create garment'}
          </button>
          <button type="button" className="btn" onClick={onDone}>Cancel</button>
          {existing && (
            <button
              type="button" className="btn" style={{ marginLeft: 'auto', color: 'var(--danger)', borderColor: 'var(--danger)' }}
              onClick={() => { removeProduct(existing.id); onDone() }}
            >
              <Icon name="x" size={14} /> Delete
            </button>
          )}
        </div>
      </div>

      <div>
        <div className="editor__preview">
          <Viewer3D
            spec={{
              kind: draft.kind, fit: draft.fit, fabric: draft.fabric, seed: draft.seed,
              color: colorway.hex, accent: colorway.accent ?? colorway.hex, angle: studio.angle,
            }}
            label={draft.name || 'New garment'}
            preset={studio.preset} bloom={studio.bloom} bloomStrength={studio.bloomStrength}
            grid={studio.grid} exposure={studio.exposure} showHud={false} showTelemetry autoRotate
          />
        </div>
        <div className="swatchrow" style={{ marginTop: 12 }}>
          {draft.colorways.map((cw, index) => (
            <button
              key={index} type="button" style={{ background: cw.hex, width: 30, height: 30 }}
              aria-pressed={index === colorIndex} aria-label={`Preview ${cw.name}`}
              onClick={() => setColorIndex(index)}
            />
          ))}
        </div>
        <p className="field__hint" style={{ marginTop: 10 }}>
          The preview is the same renderer the shop uses. Whatever you see here is what customers get.
        </p>
      </div>
    </div>
  )
}
