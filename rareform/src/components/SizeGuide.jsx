import { useRef } from 'react'
import { useFocusTrap, useLockBody } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

const TABLES = {
  apparel: {
    head: ['Size', 'Chest (cm)', 'Waist (cm)', 'Length (cm)'],
    rows: [
      ['XXS', '84–88', '68–72', '64'], ['XS', '88–92', '72–76', '66'], ['S', '92–98', '76–82', '68'],
      ['M', '98–104', '82–88', '70'], ['L', '104–112', '88–96', '72'], ['XL', '112–120', '96–104', '74'],
      ['XXL', '120–128', '104–112', '76'],
    ],
  },
  waist: {
    head: ['Waist', 'Waist (cm)', 'Hip (cm)', 'Inseam (cm)'],
    rows: [
      ['26', '66', '90', '76'], ['28', '71', '95', '78'], ['30', '76', '100', '80'], ['32', '81', '105', '81'],
      ['34', '86', '110', '82'], ['36', '91', '115', '83'], ['38', '96', '120', '84'],
    ],
  },
  shoe: {
    head: ['UK', 'EU', 'US', 'Foot length (cm)'],
    rows: [
      ['UK5', '38', '6', '24.0'], ['UK6', '39.5', '7', '24.8'], ['UK7', '41', '8', '25.7'], ['UK8', '42', '9', '26.5'],
      ['UK9', '43.5', '10', '27.3'], ['UK10', '44.5', '11', '28.2'], ['UK11', '46', '12', '29.0'],
    ],
  },
  one: { head: ['Size', 'Fits'], rows: [['One size', 'Adjustable / universal fit']] },
}

export default function SizeGuide({ open, sizeType = 'apparel', onClose }) {
  const panelRef = useRef(null)
  useLockBody(open)
  useFocusTrap(open, panelRef)
  if (!open) return null
  const table = TABLES[sizeType] ?? TABLES.apparel

  return (
    <>
      <div className="scrim" onClick={onClose} />
      <div className="modal" role="dialog" aria-modal="true" aria-label="Size guide">
        <div className="modal__panel" ref={panelRef}>
          <header className="modal__head">
            <Icon name="ruler" size={19} />
            <h2>Size guide</h2>
            <button type="button" className="icon-btn" onClick={onClose} aria-label="Close size guide"><Icon name="x" /></button>
          </header>
          <div className="modal__body">
            <p className="muted" style={{ fontSize: 13.5, marginBottom: 16 }}>
              Measurements are body measurements, not garment measurements. Between sizes on an oversized cut? Take the smaller one.
            </p>
            <table className="size">
              <thead><tr>{table.head.map(h => <th key={h} scope="col">{h}</th>)}</tr></thead>
              <tbody>
                {table.rows.map(row => (
                  <tr key={row[0]}>{row.map((cell, i) => (i === 0 ? <th key={i} scope="row">{cell}</th> : <td key={i}>{cell}</td>))}</tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </>
  )
}
