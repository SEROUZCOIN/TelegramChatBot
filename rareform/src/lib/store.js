import { useCallback, useEffect, useRef, useState } from 'react'

export function usePersistentState(key, initial) {
  const [value, setValue] = useState(() => {
    try {
      const saved = window.localStorage.getItem(key)
      if (saved !== null) return JSON.parse(saved)
    } catch {
      /* fall through to the default */
    }
    return typeof initial === 'function' ? initial() : initial
  })
  useEffect(() => {
    try {
      window.localStorage.setItem(key, JSON.stringify(value))
    } catch {
      /* storage can be unavailable in private windows — state still works */
    }
  }, [key, value])
  return [value, setValue]
}

export function useToasts() {
  const [toasts, setToasts] = useState([])
  const timers = useRef(new Map())

  const dismiss = useCallback(id => {
    setToasts(list => list.filter(t => t.id !== id))
    const timer = timers.current.get(id)
    if (timer) {
      clearTimeout(timer)
      timers.current.delete(id)
    }
  }, [])

  const push = useCallback((message, options = {}) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`
    setToasts(list => [...list.slice(-2), { id, message, ...options }])
    timers.current.set(id, setTimeout(() => dismiss(id), options.duration ?? 3600))
    return id
  }, [dismiss])

  useEffect(() => () => timers.current.forEach(clearTimeout), [])
  return { toasts, push, dismiss }
}

export function useMediaQuery(query) {
  const [matches, setMatches] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(query).matches : false)
  useEffect(() => {
    if (!window.matchMedia) return undefined
    const list = window.matchMedia(query)
    const onChange = event => setMatches(event.matches)
    setMatches(list.matches)
    list.addEventListener('change', onChange)
    return () => list.removeEventListener('change', onChange)
  }, [query])
  return matches
}

export function useLockBody(locked) {
  useEffect(() => {
    if (!locked) return undefined
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = previous }
  }, [locked])
}

// Traps tab focus inside an open dialog and restores it to the opener on close.
export function useFocusTrap(active, containerRef) {
  useEffect(() => {
    if (!active || !containerRef.current) return undefined
    const container = containerRef.current
    const opener = document.activeElement
    const selector = 'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])'

    const focusables = () => Array.from(container.querySelectorAll(selector)).filter(el => el.offsetParent !== null)
    const first = focusables()[0]
    first?.focus()

    const onKey = event => {
      if (event.key !== 'Tab') return
      const items = focusables()
      if (!items.length) return
      const start = items[0]
      const end = items[items.length - 1]
      if (event.shiftKey && document.activeElement === start) {
        event.preventDefault()
        end.focus()
      } else if (!event.shiftKey && document.activeElement === end) {
        event.preventDefault()
        start.focus()
      }
    }

    container.addEventListener('keydown', onKey)
    return () => {
      container.removeEventListener('keydown', onKey)
      if (opener instanceof HTMLElement) opener.focus()
    }
  }, [active, containerRef])
}

export function useReducedMotion() {
  return useMediaQuery('(prefers-reduced-motion: reduce)')
}

// The active currency is a store setting, so formatting reads it at call time.
let currency = 'GBP'
export function setCurrency(next) { currency = next }

export const money = (value, digits = 0) =>
  new Intl.NumberFormat('en-GB', { style: 'currency', currency, maximumFractionDigits: digits }).format(value)

export const lineKey = (productId, size, colorName) => `${productId}::${size}::${colorName}`
