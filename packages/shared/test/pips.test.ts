import { describe, expect, it } from 'vitest';
import {
  computeSignalMetrics,
  normalizeSymbol,
  pipsBetween,
  resolvePipSize,
  riskReward,
  signedPips,
  validateLevels,
} from '../src/pips';

describe('resolvePipSize', () => {
  it('uses 0.0001 for standard FX pairs', () => {
    expect(resolvePipSize('EURUSD')).toBe(0.0001);
    expect(resolvePipSize('GBPUSD')).toBe(0.0001);
  });

  it('uses 0.01 for JPY-quoted pairs', () => {
    expect(resolvePipSize('USDJPY')).toBe(0.01);
    expect(resolvePipSize('EURJPY')).toBe(0.01);
  });

  it('handles metals and indices', () => {
    expect(resolvePipSize('XAUUSD')).toBe(0.1);
    expect(resolvePipSize('XAGUSD')).toBe(0.01);
    expect(resolvePipSize('US30')).toBe(1);
    expect(resolvePipSize('NAS100')).toBe(1);
  });

  it('sees through broker symbol decoration', () => {
    expect(normalizeSymbol('EUR/USD')).toBe('EURUSD');
    expect(normalizeSymbol('eurusd')).toBe('EURUSD');
    expect(resolvePipSize('XAUUSD.PRO')).toBe(0.1);
  });

  it('lets an explicit override win, since brokers disagree', () => {
    expect(resolvePipSize('XAUUSD', 0.01)).toBe(0.01);
    expect(resolvePipSize('EURUSD', null)).toBe(0.0001);
  });
});

describe('pip arithmetic', () => {
  it('rounds away floating point noise', () => {
    // 1.0850 - 1.0800 evaluates to 0.004999999999999893 in IEEE 754.
    expect(pipsBetween(1.085, 1.08, 0.0001)).toBe(50);
  });

  it('reports profit as positive for both directions', () => {
    expect(signedPips('BUY', 1.08, 1.085, 0.0001)).toBe(50);
    expect(signedPips('SELL', 1.085, 1.08, 0.0001)).toBe(50);
  });

  it('reports a losing exit as negative for both directions', () => {
    expect(signedPips('BUY', 1.085, 1.08, 0.0001)).toBe(-50);
    expect(signedPips('SELL', 1.08, 1.085, 0.0001)).toBe(-50);
  });

  it('computes reward-to-risk, and refuses a zero-risk trade', () => {
    expect(riskReward(1.08, 1.075, 1.095)).toBe(3);
    expect(riskReward(1.08, 1.08, 1.09)).toBeNull();
  });
});

describe('computeSignalMetrics', () => {
  it('derives stop distance, target distances and R:R from raw levels', () => {
    const m = computeSignalMetrics({
      symbol: 'EURUSD',
      direction: 'BUY',
      entryLow: 1.08,
      entryHigh: 1.08,
      sl: 1.075,
      tp1: 1.085,
      tp2: 1.09,
      tp3: 1.095,
    });

    expect(m.slPips).toBe(50);
    expect(m.targets.map((t) => t.pips)).toEqual([50, 100, 150]);
    expect(m.targets.map((t) => t.rr)).toEqual([1, 2, 3]);
    expect(m.maxRR).toBe(3);
  });

  it('uses the midpoint of an entry zone rather than the favourable edge', () => {
    const m = computeSignalMetrics({
      symbol: 'EURUSD',
      direction: 'BUY',
      entryLow: 1.079,
      entryHigh: 1.081,
      sl: 1.075,
      tp1: 1.09,
    });

    // Midpoint 1.0800 => 50 pips of risk, not 40 measured from the best fill.
    expect(m.entryRef).toBe(1.08);
    expect(m.slPips).toBe(50);
  });

  it('skips undefined targets instead of emitting holes', () => {
    const m = computeSignalMetrics({
      symbol: 'USDJPY',
      direction: 'SELL',
      entryLow: 150,
      entryHigh: 150,
      sl: 150.5,
      tp1: 149.5,
      tp2: null,
      tp3: 148.5,
    });

    expect(m.targets.map((t) => t.level)).toEqual([1, 3]);
    expect(m.targets[0].pips).toBe(50);
    expect(m.targets[1].pips).toBe(150);
  });
});

describe('validateLevels', () => {
  const base = {
    symbol: 'EURUSD',
    direction: 'BUY' as const,
    entryLow: 1.08,
    entryHigh: 1.08,
    sl: 1.075,
    tp1: 1.09,
  };

  it('accepts a well-formed setup', () => {
    expect(validateLevels(base)).toEqual([]);
  });

  it('catches a stop on the wrong side of entry', () => {
    expect(validateLevels({ ...base, sl: 1.085 }).join(' ')).toMatch(/below the entry zone/);
    expect(
      validateLevels({ ...base, direction: 'SELL', sl: 1.075, tp1: 1.07 }).join(' '),
    ).toMatch(/above the entry zone/);
  });

  it('catches an inverted entry zone', () => {
    expect(validateLevels({ ...base, entryLow: 1.09, entryHigh: 1.08 }).join(' ')).toMatch(
      /low is above/,
    );
  });

  it('catches targets that do not ladder outward', () => {
    const problems = validateLevels({ ...base, tp1: 1.095, tp2: 1.085 });
    expect(problems.join(' ')).toMatch(/ordered outward/);
  });

  it('requires at least one target', () => {
    expect(validateLevels({ ...base, tp1: null }).join(' ')).toMatch(/at least one take-profit/i);
  });
});
