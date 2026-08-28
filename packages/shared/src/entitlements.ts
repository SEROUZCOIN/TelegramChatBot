import { highestPlan, planSatisfies, type PlanCode } from './domain';

/**
 * Entitlement resolution.
 *
 * This runs on the server and only on the server. The mobile app never decides
 * what it is allowed to see: it renders whatever `GET /me/entitlements` returns
 * and asks again for anything gated. A client that computed its own access
 * would be one patched binary away from a free Ultra subscription.
 */

export interface ActiveSubscriptionLike {
  planCode: PlanCode;
  status: string;
  expiresAt: Date | string | null;
}

export interface Entitlements {
  plan: PlanCode;
  canViewSignals: boolean;
  canViewCourses: boolean;
  canBookCoaching: boolean;
  /** Ultra buys the structured beginner-to-pro curriculum plus a mentor. */
  canAccessMentorship: boolean;
  /** Ads are suppressed for the tiers that paid to not see them. */
  showAds: boolean;
  expiresAt: Date | null;
}

function isLive(sub: ActiveSubscriptionLike, now: Date): boolean {
  if (sub.status !== 'ACTIVE') return false;
  if (!sub.expiresAt) return true; // one-time purchases never lapse
  const exp = sub.expiresAt instanceof Date ? sub.expiresAt : new Date(sub.expiresAt);
  return exp.getTime() > now.getTime();
}

export function resolveEntitlements(
  subscriptions: readonly ActiveSubscriptionLike[],
  now: Date = new Date(),
): Entitlements {
  const live = subscriptions.filter((s) => isLive(s, now));
  const plan = highestPlan(live.map((s) => s.planCode));

  const expiries = live
    .map((s) => (s.expiresAt ? new Date(s.expiresAt).getTime() : Infinity))
    .filter((t) => Number.isFinite(t));
  const expiresAt = expiries.length ? new Date(Math.max(...expiries)) : null;

  return {
    plan,
    canViewSignals: planSatisfies(plan, 'SIGNALS'),
    canViewCourses: planSatisfies(plan, 'NORMAL'),
    canBookCoaching: planSatisfies(plan, 'PRO'),
    canAccessMentorship: planSatisfies(plan, 'ULTRA'),
    showAds: !planSatisfies(plan, 'PRO'),
    expiresAt,
  };
}

/** Whether a viewer on `plan` may open content gated at `minPlan`. */
export function canAccessContent(plan: PlanCode, minPlan: PlanCode): boolean {
  return planSatisfies(plan, minPlan);
}
