export const theme = {
  bg: '#0b1120',
  surface: '#111a2e',
  surface2: '#16213a',
  border: '#24314f',
  text: '#e6ecf7',
  muted: '#93a3c0',
  accent: '#3b82f6',
  buy: '#22c55e',
  sell: '#ef4444',
  warn: '#f59e0b',
  radius: 14,
  space: (n: number) => n * 4,
} as const;

export const statusColor = (status: string): string => {
  if (status.startsWith('CLOSED_WIN') || status.endsWith('_HIT')) return theme.buy;
  if (status === 'CLOSED_LOSS') return theme.sell;
  if (status === 'CLOSED_BE') return theme.muted;
  if (status === 'BE_SET') return theme.warn;
  return theme.accent;
};
