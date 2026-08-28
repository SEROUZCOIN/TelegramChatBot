import { describe, expect, it } from 'vitest';
import { computeStats } from '../src/stats';
import type { ClosedSignalRecord } from '../src/stats';

const at = (day: number) => new Date(2026, 0, day);

describe('computeStats', () => {
  it('excludes break-even and cancelled signals from the win rate', () => {
    const signals: ClosedSignalRecord[] = [
      { status: 'CLOSED_WIN', resultPips: 100, closedAt: at(1) },
      { status: 'CLOSED_WIN', resultPips: 50, closedAt: at(2) },
      { status: 'CLOSED_LOSS', resultPips: -50, closedAt: at(3) },
      { status: 'CLOSED_BE', resultPips: 0, closedAt: at(4) },
      { status: 'CANCELLED', closedAt: at(5) },
    ];

    const s = computeStats(signals);

    // 2 wins / 3 decided trades — the scratch and the cancelled setup are not
    // losses, and padding the denominator with them would misreport the record.
    expect(s.winRate).toBe(66.7);
    expect(s.wins).toBe(2);
    expect(s.losses).toBe(1);
    expect(s.breakEven).toBe(1);
    expect(s.cancelled).toBe(1);
  });

  it('totals pips across wins and losses', () => {
    const s = computeStats([
      { status: 'CLOSED_WIN', resultPips: 120, closedAt: at(1) },
      { status: 'CLOSED_LOSS', resultPips: -40, closedAt: at(2) },
    ]);

    expect(s.totalPips).toBe(80);
    expect(s.avgWinPips).toBe(120);
    expect(s.avgLossPips).toBe(40);
    expect(s.profitFactor).toBe(3);
  });

  it('counts open signals separately and leaves the win rate untouched', () => {
    const s = computeStats([
      { status: 'ACTIVE', closedAt: null },
      { status: 'BE_SET', closedAt: null },
      { status: 'CLOSED_WIN', resultPips: 30, closedAt: at(1) },
    ]);

    expect(s.open).toBe(2);
    expect(s.winRate).toBe(100);
    expect(s.total).toBe(3);
  });

  it('reports no win rate before any trade is decided', () => {
    expect(computeStats([{ status: 'PUBLISHED' }]).winRate).toBeNull();
    expect(computeStats([]).winRate).toBeNull();
  });

  it('tracks the current and best streak, with scratches not breaking a run', () => {
    const s = computeStats([
      { status: 'CLOSED_WIN', resultPips: 10, closedAt: at(1) },
      { status: 'CLOSED_WIN', resultPips: 10, closedAt: at(2) },
      { status: 'CLOSED_BE', resultPips: 0, closedAt: at(3) },
      { status: 'CLOSED_WIN', resultPips: 10, closedAt: at(4) },
      { status: 'CLOSED_LOSS', resultPips: -10, closedAt: at(5) },
    ]);

    expect(s.bestStreak).toBe(3);
    expect(s.currentStreak).toBe(-1);
  });

  it('leaves profit factor undefined while there are no losses', () => {
    const s = computeStats([{ status: 'CLOSED_WIN', resultPips: 10, closedAt: at(1) }]);
    expect(s.profitFactor).toBeNull();
  });
});
