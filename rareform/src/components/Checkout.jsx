import { useRef, useState } from 'react'
import { useFocusTrap, useLockBody, money } from '../lib/store.js'
import { Icon } from '../lib/icons.jsx'

const STEPS = ['Contact', 'Delivery', 'Payment']

export default function Checkout({ open, total, onClose, onComplete }) {
  const [step, setStep] = useState(0)
  const [done, setDone] = useState(false)
  const panelRef = useRef(null)
  useLockBody(open)
  useFocusTrap(open, panelRef)

  if (!open) return null

  const next = event => {
    event.preventDefault()
    if (step < STEPS.length - 1) {
      setStep(step + 1)
      return
    }
    setDone(true)
    onComplete()
  }

  const close = () => {
    setStep(0)
    setDone(false)
    onClose()
  }

  return (
    <>
      <div className="scrim" onClick={close} />
      <div className="modal" role="dialog" aria-modal="true" aria-label="Checkout">
        <div className="modal__panel" ref={panelRef}>
          <header className="modal__head">
            <Icon name="lock" size={18} />
            <h2>{done ? 'Order placed' : 'Checkout'}</h2>
            <button type="button" className="icon-btn" onClick={close} aria-label="Close checkout"><Icon name="x" /></button>
          </header>

          <div className="modal__body">
            {done
              ? (
                <div style={{ textAlign: 'center', padding: '20px 0 8px' }}>
                  <div style={{ display: 'grid', placeItems: 'center', width: 56, height: 56, borderRadius: '50%', background: 'var(--signal)', color: 'var(--signal-ink)', margin: '0 auto 18px' }}>
                    <Icon name="check" size={26} strokeWidth={2.4} />
                  </div>
                  <h3 style={{ fontSize: 20, textTransform: 'uppercase' }}>Thank you</h3>
                  <p className="muted" style={{ marginTop: 10, fontSize: 13.5 }}>
                    This is a demonstration storefront, so no payment was taken and nothing will ship.
                    Your bag has been cleared so you can keep exploring.
                  </p>
                  <button type="button" className="btn btn--primary" style={{ marginTop: 20 }} onClick={close}>Keep shopping</button>
                </div>
              )
              : (
                <>
                  <div className="steps" aria-hidden="true">
                    {STEPS.map((label, index) => <div key={label} data-on={index <= step} />)}
                  </div>
                  <p className="mono muted" style={{ marginBottom: 16 }}>Step {step + 1} of {STEPS.length} — {STEPS[step]}</p>

                  <form className="checkout" onSubmit={next}>
                    {step === 0 && (
                      <>
                        <div className="field">
                          <label htmlFor="co-email">Email</label>
                          <input id="co-email" type="email" required placeholder="you@example.com" autoComplete="email" />
                        </div>
                        <div className="field">
                          <label htmlFor="co-name">Full name</label>
                          <input id="co-name" required placeholder="Alex Moreno" autoComplete="name" />
                        </div>
                      </>
                    )}
                    {step === 1 && (
                      <>
                        <div className="field">
                          <label htmlFor="co-addr">Address</label>
                          <input id="co-addr" required placeholder="12 Bridge Lane" autoComplete="street-address" />
                        </div>
                        <div className="field--row">
                          <div className="field">
                            <label htmlFor="co-city">City</label>
                            <input id="co-city" required placeholder="London" autoComplete="address-level2" />
                          </div>
                          <div className="field">
                            <label htmlFor="co-post">Postcode</label>
                            <input id="co-post" required placeholder="E1 6AN" autoComplete="postal-code" />
                          </div>
                        </div>
                      </>
                    )}
                    {step === 2 && (
                      <>
                        <div className="field">
                          <label htmlFor="co-card">Card number</label>
                          <input id="co-card" required placeholder="4242 4242 4242 4242" inputMode="numeric" />
                        </div>
                        <div className="field--row">
                          <div className="field">
                            <label htmlFor="co-exp">Expiry</label>
                            <input id="co-exp" required placeholder="04 / 29" />
                          </div>
                          <div className="field">
                            <label htmlFor="co-cvc">CVC</label>
                            <input id="co-cvc" required placeholder="123" inputMode="numeric" />
                          </div>
                        </div>
                        <p className="mono muted" style={{ fontSize: 9.5 }}>
                          Demo only — do not enter a real card. Nothing is transmitted or stored.
                        </p>
                      </>
                    )}

                    <div style={{ display: 'flex', gap: 10, marginTop: 8 }}>
                      {step > 0 && (
                        <button type="button" className="btn" onClick={() => setStep(step - 1)}>
                          <Icon name="arrowLeft" size={14} /> Back
                        </button>
                      )}
                      <button type="submit" className="btn btn--signal" style={{ flex: 1 }}>
                        {step === STEPS.length - 1 ? `Pay ${money(total)}` : 'Continue'}
                      </button>
                    </div>
                  </form>
                </>
              )}
          </div>
        </div>
      </div>
    </>
  )
}
