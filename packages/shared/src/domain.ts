/**
 * Core domain vocabulary. Every surface (API, admin, mobile, Telegram bot)
 * imports these — there is exactly one definition of a plan tier, a signal
 * status, and an update type in the entire system.
 */

/** Subscription tiers, ordered weakest to strongest. */
export const PLAN_CODES = ['FREE', 'SIGNALS', 'NORMAL', 'PRO', 'ULTRA'] as const;
export type PlanCode = (typeof PLAN_CODES)[number];

/**
 * Access is hierarchical: a higher tier sees everything a lower tier sees.
 * ULTRA is "beginner to pro" so it necessarily contains the PRO coaching and
 * the NORMAL video library and the SIGNALS feed.
 */
export const PLAN_RANK: Record<PlanCode, number> = {
  FREE: 0,
  SIGNALS: 1,
  NORMAL: 2,
  PRO: 3,
  ULTRA: 4,
};

/** True when `held` satisfies a `required` minimum tier. */
export function planSatisfies(held: PlanCode, required: PlanCode): boolean {
  return PLAN_RANK[held] >= PLAN_RANK[required];
}

/** The strongest tier among a set of active subscriptions. */
export function highestPlan(codes: PlanCode[]): PlanCode {
  return codes.reduce<PlanCode>(
    (best, c) => (PLAN_RANK[c] > PLAN_RANK[best] ? c : best),
    'FREE',
  );
}

export const TRADE_DIRECTIONS = ['BUY', 'SELL'] as const;
export type TradeDirection = (typeof TRADE_DIRECTIONS)[number];

export const ORDER_TYPES = ['MARKET', 'LIMIT', 'STOP'] as const;
export type OrderType = (typeof ORDER_TYPES)[number];

export const SIGNAL_STATUSES = [
  'DRAFT',
  'PUBLISHED',
  'ACTIVE',
  'BE_SET',
  'TP1_HIT',
  'TP2_HIT',
  'TP3_HIT',
  'CLOSED_WIN',
  'CLOSED_BE',
  'CLOSED_LOSS',
  'CANCELLED',
] as const;
export type SignalStatus = (typeof SIGNAL_STATUSES)[number];

export const SIGNAL_UPDATE_TYPES = [
  'ENTRY_HIT',
  'MOVED_TO_BE',
  'TP1_HIT',
  'TP2_HIT',
  'TP3_HIT',
  'SL_HIT',
  'PARTIAL_CLOSE',
  'CLOSE_WIN',
  'CLOSE_LOSS',
  'CANCELLED',
  'COMMENT',
] as const;
export type SignalUpdateType = (typeof SIGNAL_UPDATE_TYPES)[number];

export const SUBSCRIPTION_STATUSES = [
  'PENDING',
  'ACTIVE',
  'PAST_DUE',
  'CANCELLED',
  'EXPIRED',
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export const PAYMENT_PROVIDERS = ['STRIPE', 'CRYPTO', 'BANK', 'IAP'] as const;
export type PaymentProviderCode = (typeof PAYMENT_PROVIDERS)[number];

export const PAYMENT_STATUSES = [
  'PENDING',
  'AWAITING_REVIEW',
  'PAID',
  'FAILED',
  'REFUNDED',
] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

/**
 * Which rails a plan may be bought through.
 *
 * Default across the platform is EXTERNAL (Stripe / crypto / bank), which keeps
 * ~97% of revenue. Apple guideline 3.1.3(d) explicitly allows this for the
 * one-to-one coaching tiers (PRO, ULTRA). The NORMAL tier sells recorded video,
 * which guideline 3.1.1 says must use in-app purchase — so if App Review
 * objects, flip that single plan row to IAP or BOTH. No code change, no
 * rebuild: the provider is already implemented and registered.
 */
export const PAYMENT_MODES = ['EXTERNAL', 'IAP', 'BOTH'] as const;
export type PaymentMode = (typeof PAYMENT_MODES)[number];

export const AD_SLOTS = [
  'FEED_INLINE',
  'SIGNAL_DETAIL',
  'COURSE_LIST',
  'INTERSTITIAL',
  'REWARDED',
] as const;
export type AdSlot = (typeof AD_SLOTS)[number];

export const USER_ROLES = ['USER', 'COACH', 'ADMIN'] as const;
export type UserRole = (typeof USER_ROLES)[number];

export const COACHING_STATUSES = [
  'REQUESTED',
  'SCHEDULED',
  'LIVE',
  'COMPLETED',
  'CANCELLED',
  'NO_SHOW',
] as const;
export type CoachingStatus = (typeof COACHING_STATUSES)[number];

export const LINK_CATEGORIES = ['SOCIAL', 'CHANNEL', 'BROKER', 'SUPPORT', 'OTHER'] as const;
export type LinkCategory = (typeof LINK_CATEGORIES)[number];
