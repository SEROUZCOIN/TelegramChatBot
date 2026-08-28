import type { SignalStatus } from './domain';
import { roundTo } from './pips';

/**
 * Performance statistics computed from the signal ledger.
 *
 * Most competing services publish a win rate with nothing behind it. Every
 * number here is derived from closed signals in the database, so the figure on
 * the marketing screen and the figure a subscriber could total up by hand from
 * the feed are the same number by construction.
 */

export interface ClosedSignalRecord {
  status: SignalStatus;
  /** Realised result in pips, signed. Null while the signal is still open. */
  resultPips?: number | null;
  /** Planned reward:risk at the furthest target, for the average-R:R figure. */
  plannedRR?: number | null;
  closedAt?: Date | string | null;
}

export interface SignalStats {
  total: number;
  open: number;
  wins: number;
  losses: number;
  breakEven: number;
  cancelled: number;
  /**
   * wins / (wins + losses). Break-even and cancelled signals are excluded from
   * the denominator — a scratch trade is not a loss, and a cancelled setup was
   * never taken, so neither belongs in a win rate.
   */
  winRate: number | null;
  totalPips: number;
  avgWinPips: number | null;
  avgLossPips: number | null;
  /** Gross win pips / gross loss pips. Null when there are no losses yet. */
  profitFactor: number | null;
  avgPlannedRR: number | null;
  currentStreak: number;
  bestStreak: number;
}

const OPEN_STATUSES: readonly SignalStatus[] = [
  'DRAFT',
  'PUBLISHED',
  'ACTIVE',
  'BE_SET',
  'TP1_HIT',
  'TP2_HIT',
  'TP3_HIT',
];

export function computeStats(signals: readonly ClosedSignalRecord[]): SignalStats {
  let open = 0;
  let wins = 0;
  let losses = 0;
  let breakEven = 0;
  let cancelled = 0;
  let totalPips = 0;
  let grossWin = 0;
  let grossLoss = 0;
  let currentStreak = 0;
  let bestStreak = 0;

  const rrValues: number[] = [];

  // Oldest first, so the streak walk ends on the most recent result.
  const ordered = [...signals].sort((a, b) => toTime(a.closedAt) - toTime(b.closedAt));

  for (const s of ordered) {
    if (s.plannedRR != null) rrValues.push(s.plannedRR);

    if (OPEN_STATUSES.includes(s.status)) {
      open += 1;
      continue;
    }
    if (s.status === 'CANCELLED') {
      cancelled += 1;
      continue;
    }

    const pips = s.resultPips ?? 0;
    totalPips += pips;

    if (s.status === 'CLOSED_WIN') {
      wins += 1;
      grossWin += Math.max(pips, 0);
      currentStreak = currentStreak >= 0 ? currentStreak + 1 : 1;
    } else if (s.status === 'CLOSED_LOSS') {
      losses += 1;
      grossLoss += Math.abs(Math.min(pips, 0));
      currentStreak = currentStreak <= 0 ? currentStreak - 1 : -1;
    } else if (s.status === 'CLOSED_BE') {
      breakEven += 1;
      // A scratch neither extends nor breaks a run.
    }

    if (currentStreak > bestStreak) bestStreak = currentStreak;
  }

  const decided = wins + losses;

  return {
    total: signals.length,
    open,
    wins,
    losses,
    breakEven,
    cancelled,
    winRate: decided > 0 ? roundTo((wins / decided) * 100, 1) : null,
    totalPips: roundTo(totalPips),
    avgWinPips: wins > 0 ? roundTo(grossWin / wins) : null,
    avgLossPips: losses > 0 ? roundTo(grossLoss / losses) : null,
    profitFactor: grossLoss > 0 ? roundTo(grossWin / grossLoss, 2) : null,
    avgPlannedRR: rrValues.length
      ? roundTo(rrValues.reduce((a, b) => a + b, 0) / rrValues.length, 2)
      : null,
    currentStreak,
    bestStreak,
  };
}

function toTime(d: Date | string | null | undefined): number {
  if (!d) return 0;
  return d instanceof Date ? d.getTime() : new Date(d).getTime();
}
