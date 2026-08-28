import type { TradeDirection } from './domain';

/**
 * Pip arithmetic.
 *
 * Every derived number a subscriber sees — distance to stop, distance to each
 * target, risk:reward — is computed here from the raw prices. Nothing is
 * hand-typed in the admin composer, so a signal cannot advertise "1:3 R:R"
 * while its actual levels say otherwise.
 */

/**
 * Default pip size per instrument family.
 *
 * Brokers disagree about instruments (some quote gold to 2dp, some to 3), so
 * this is only a default: every signal carries an optional `pipSize` override
 * the admin can set per instrument. A fixed table alone would eventually be
 * wrong for someone's feed.
 */
const PIP_SIZE_RULES: ReadonlyArray<{ test: (s: string) => boolean; pip: number }> = [
  { test: (s) => s.startsWith('XAU') || s.startsWith('GOLD'), pip: 0.1 },
  { test: (s) => s.startsWith('XAG') || s.startsWith('SILVER'), pip: 0.01 },
  { test: (s) => s.startsWith('BTC') || s.startsWith('ETH'), pip: 1 },
  { test: (s) => /^(US30|US100|NAS100|SPX500|US500|GER40|DE40|UK100|JP225)/.test(s), pip: 1 },
  { test: (s) => /^(WTI|USOIL|UKOIL|BRENT)/.test(s), pip: 0.01 },
  // JPY-quoted FX pairs are quoted to 3dp, so a pip is 0.01 rather than 0.0001.
  { test: (s) => /^[A-Z]{3}JPY/.test(s), pip: 0.01 },
  { test: (s) => /^[A-Z]{6}$/.test(s), pip: 0.0001 },
];

const DEFAULT_PIP_SIZE = 0.0001;

/**
 * Strip the broker-specific decoration MT5 symbols carry (`EURUSD.m`,
 * `EURUSD_i`, `EUR/USD`, `XAUUSD-ECN`) down to the bare instrument.
 */
export function normalizeSymbol(symbol: string): string {
  return symbol
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/(MICRO|CASH|ECN|PRO|RAW)$/, '');
}

export function resolvePipSize(symbol: string, override?: number | null): number {
  if (override && override > 0) return override;
  const s = normalizeSymbol(symbol);
  return PIP_SIZE_RULES.find((r) => r.test(s))?.pip ?? DEFAULT_PIP_SIZE;
}

/** Round away binary floating-point noise (1.0850 - 1.0800 = 0.004999…). */
export function roundTo(value: number, decimals = 1): number {
  const f = 10 ** decimals;
  return Math.round((value + Number.EPSILON) * f) / f;
}

/** Absolute distance between two prices, in pips. */
export function pipsBetween(a: number, b: number, pipSize: number): number {
  return roundTo(Math.abs(a - b) / pipSize);
}

/**
 * Distance from entry to exit in pips, signed so that positive is always
 * profit — for a SELL, price falling is the gain.
 */
export function signedPips(
  direction: TradeDirection,
  entry: number,
  exit: number,
  pipSize: number,
): number {
  const raw = direction === 'BUY' ? exit - entry : entry - exit;
  return roundTo(raw / pipSize);
}

/**
 * Reward-to-risk as a multiple. `null` when the stop sits on the entry, which
 * would make risk zero and the ratio meaningless.
 */
export function riskReward(entry: number, sl: number, tp: number): number | null {
  const risk = Math.abs(entry - sl);
  if (risk === 0) return null;
  return roundTo(Math.abs(tp - entry) / risk, 2);
}

export interface SignalLevels {
  symbol: string;
  direction: TradeDirection;
  entryLow: number;
  entryHigh: number;
  sl: number;
  tp1?: number | null;
  tp2?: number | null;
  tp3?: number | null;
  /** Price at which the stop should be pulled to break-even. */
  beTrigger?: number | null;
  pipSize?: number | null;
}

export interface SignalMetrics {
  pipSize: number;
  /** Midpoint of the entry zone — the reference price for every derived number. */
  entryRef: number;
  slPips: number;
  targets: Array<{ level: 1 | 2 | 3; price: number; pips: number; rr: number | null }>;
  /** R:R at the furthest defined target. */
  maxRR: number | null;
}

/**
 * Derive every displayed number from the raw levels.
 *
 * The entry zone is collapsed to its midpoint. Using the favourable edge would
 * quietly flatter the R:R on every signal with a wide zone; the midpoint is the
 * number a subscriber filling anywhere in the zone actually averages toward.
 */
export function computeSignalMetrics(s: SignalLevels): SignalMetrics {
  const pipSize = resolvePipSize(s.symbol, s.pipSize);
  const entryRef = (s.entryLow + s.entryHigh) / 2;

  const targets = ([1, 2, 3] as const)
    .map((level) => {
      const price = level === 1 ? s.tp1 : level === 2 ? s.tp2 : s.tp3;
      if (price == null) return null;
      return {
        level,
        price,
        pips: pipsBetween(entryRef, price, pipSize),
        rr: riskReward(entryRef, s.sl, price),
      };
    })
    .filter((t): t is NonNullable<typeof t> => t !== null);

  return {
    pipSize,
    entryRef: roundTo(entryRef, 6),
    slPips: pipsBetween(entryRef, s.sl, pipSize),
    targets,
    maxRR: targets.length ? targets[targets.length - 1].rr : null,
  };
}

/**
 * Sanity checks on a signal's levels, as human-readable problems.
 *
 * These are warnings for the composer, not hard rejections — an unusual setup
 * is the admin's call to make, but a stop on the wrong side of entry is almost
 * always a typo and is worth catching before it reaches subscribers.
 */
export function validateLevels(s: SignalLevels): string[] {
  const problems: string[] = [];
  const entryRef = (s.entryLow + s.entryHigh) / 2;

  if (s.entryLow > s.entryHigh) {
    problems.push('Entry zone low is above entry zone high.');
  }

  if (s.direction === 'BUY' && s.sl >= entryRef) {
    problems.push('For a BUY the stop-loss must sit below the entry zone.');
  }
  if (s.direction === 'SELL' && s.sl <= entryRef) {
    problems.push('For a SELL the stop-loss must sit above the entry zone.');
  }

  const tps = [s.tp1, s.tp2, s.tp3].filter((t): t is number => t != null);
  if (tps.length === 0) {
    problems.push('At least one take-profit target is required.');
  }
  for (const tp of tps) {
    if (s.direction === 'BUY' && tp <= entryRef) {
      problems.push(`For a BUY every take-profit must sit above the entry zone (got ${tp}).`);
    }
    if (s.direction === 'SELL' && tp >= entryRef) {
      problems.push(`For a SELL every take-profit must sit below the entry zone (got ${tp}).`);
    }
  }

  // Targets must ladder outward from entry, or the TP1/TP2/TP3 labels mislead.
  const ordered = s.direction === 'BUY' ? [...tps].sort((a, b) => a - b) : [...tps].sort((a, b) => b - a);
  if (JSON.stringify(ordered) !== JSON.stringify(tps)) {
    problems.push('Take-profit targets must be ordered outward from entry (TP1 nearest).');
  }

  return problems;
}
