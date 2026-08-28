import { describe, expect, it } from 'vitest';
import { resolveEntitlements } from '../src/entitlements';
import { highestPlan, planSatisfies } from '../src/domain';

const future = new Date(Date.now() + 86_400_000);
const past = new Date(Date.now() - 86_400_000);

describe('plan hierarchy', () => {
  it('lets a higher tier see everything a lower tier sees', () => {
    expect(planSatisfies('ULTRA', 'SIGNALS')).toBe(true);
    expect(planSatisfies('PRO', 'NORMAL')).toBe(true);
    expect(planSatisfies('SIGNALS', 'NORMAL')).toBe(false);
    expect(planSatisfies('FREE', 'SIGNALS')).toBe(false);
  });

  it('picks the strongest of several held plans', () => {
    expect(highestPlan(['SIGNALS', 'ULTRA', 'NORMAL'])).toBe('ULTRA');
    expect(highestPlan([])).toBe('FREE');
  });
});

describe('resolveEntitlements', () => {
  it('gives a free user nothing but ads', () => {
    const e = resolveEntitlements([]);
    expect(e.plan).toBe('FREE');
    expect(e.canViewSignals).toBe(false);
    expect(e.canViewCourses).toBe(false);
    expect(e.showAds).toBe(true);
  });

  it('unlocks signals but not courses on the signals plan', () => {
    const e = resolveEntitlements([
      { planCode: 'SIGNALS', status: 'ACTIVE', expiresAt: future },
    ]);
    expect(e.canViewSignals).toBe(true);
    expect(e.canViewCourses).toBe(false);
    expect(e.showAds).toBe(true);
  });

  it('suppresses ads for the tiers that paid to not see them', () => {
    expect(resolveEntitlements([{ planCode: 'PRO', status: 'ACTIVE', expiresAt: future }]).showAds)
      .toBe(false);
    expect(
      resolveEntitlements([{ planCode: 'ULTRA', status: 'ACTIVE', expiresAt: null }]).showAds,
    ).toBe(false);
    expect(
      resolveEntitlements([{ planCode: 'NORMAL', status: 'ACTIVE', expiresAt: future }]).showAds,
    ).toBe(true);
  });

  it('ignores expired and non-active subscriptions', () => {
    const e = resolveEntitlements([
      { planCode: 'ULTRA', status: 'ACTIVE', expiresAt: past },
      { planCode: 'PRO', status: 'CANCELLED', expiresAt: future },
      { planCode: 'SIGNALS', status: 'ACTIVE', expiresAt: future },
    ]);
    expect(e.plan).toBe('SIGNALS');
  });

  it('treats a null expiry as a one-time purchase that never lapses', () => {
    const e = resolveEntitlements([{ planCode: 'ULTRA', status: 'ACTIVE', expiresAt: null }]);
    expect(e.plan).toBe('ULTRA');
    expect(e.canAccessMentorship).toBe(true);
    expect(e.expiresAt).toBeNull();
  });
});
