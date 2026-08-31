// A local icon set keeps the bundle small and the stroke weight consistent.
const PATHS = {
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm10 2-4.35-4.35',
  bag: 'M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4H6ZM3 6h18M16 10a4 4 0 0 1-8 0',
  heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 1 0-7.8 7.8l8.8 8.7 8.8-8.7a5.5 5.5 0 0 0 0-7.8Z',
  user: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z',
  menu: 'M3 6h18M3 12h18M3 18h18',
  x: 'M18 6 6 18M6 6l12 12',
  chevronDown: 'm6 9 6 6 6-6',
  chevronUp: 'm18 15-6-6-6 6',
  chevronRight: 'm9 18 6-6-6-6',
  arrowRight: 'M5 12h14m-6-7 7 7-7 7',
  arrowLeft: 'M19 12H5m6 7-7-7 7-7',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  check: 'm20 6-11 11-5-5',
  sliders: 'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6',
  sun: 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10ZM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  moon: 'M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z',
  rotate: 'M23 4v6h-6M1 20v-6h6M3.5 9a9 9 0 0 1 14.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0 0 20.5 15',
  reset: 'M3 12a9 9 0 1 0 3-6.7L3 8m0-5v5h5',
  zoomIn: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm10 2-4.35-4.35M11 8v6M8 11h6',
  zoomOut: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm10 2-4.35-4.35M8 11h6',
  truck: 'M1 3h15v13H1zM16 8h4l3 3v5h-7zM5.5 21a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM18.5 21a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z',
  shield: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z',
  refresh: 'M3 2v6h6M21 22v-6h-6M21 11.5A9 9 0 0 0 6.6 5.6L3 8m18 8-3.6 2.4A9 9 0 0 1 3 12.5',
  star: 'm12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.9-6.2-3.3-6.2 3.3L7 14.2l-5-4.9 6.9-1L12 2Z',
  sparkle: 'M12 2v6M12 16v6M2 12h6M16 12h6M5 5l3.5 3.5M15.5 15.5 19 19M19 5l-3.5 3.5M8.5 15.5 5 19',
  ruler: 'M2 15 15 2l7 7L9 22l-7-7ZM7 10l2 2M10 7l2 2M4 13l2 2',
  layers: 'm12 2 9 5-9 5-9-5 9-5ZM3 17l9 5 9-5M3 12l9 5 9-5',
  cube: 'm12 2 9 5v10l-9 5-9-5V7l9-5ZM3 7l9 5 9-5M12 12v10',
  leaf: 'M11 20A7 7 0 0 1 4 13c0-6 8-11 16-11 0 8-4 16-11 16ZM4 21c2-6 5-9 9-11',
  grid: 'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z',
  maximize: 'M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M16 21h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3',
  lock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4',
  clock: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20ZM12 6v6l4 2',
  corner: 'm15 10 5 5-5 5M4 4v7a4 4 0 0 0 4 4h12',
}

export function Icon({ name, size = 18, strokeWidth = 1.6, fill = 'none', ...rest }) {
  const d = PATHS[name]
  if (!d) return null
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor"
      strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"
      aria-hidden="true" focusable="false" {...rest}
    >
      <path d={d} />
    </svg>
  )
}

export function Stars({ value, size = 12 }) {
  return (
    <span style={{ display: 'inline-flex', gap: 1 }} aria-hidden="true">
      {[0, 1, 2, 3, 4].map(i => (
        <Icon
          key={i} name="star" size={size} strokeWidth={1.4}
          fill={value - i >= 0.5 ? 'currentColor' : 'none'}
          style={{ opacity: value - i >= 0.5 ? 1 : 0.35 }}
        />
      ))}
    </span>
  )
}
