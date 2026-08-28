import { z } from 'zod';
import {
  AD_SLOTS,
  COACHING_STATUSES,
  LINK_CATEGORIES,
  ORDER_TYPES,
  PAYMENT_PROVIDERS,
  PLAN_CODES,
  SIGNAL_UPDATE_TYPES,
  TRADE_DIRECTIONS,
} from './domain';

/**
 * Wire contracts. The API validates with these, the admin panel builds forms
 * from them, the mobile app types its responses off them, and the MT5 bridge
 * posts against them — so a field can never mean two different things on two
 * different surfaces.
 */

const price = z.number().finite().positive();

/**
 * The canonical signal payload.
 *
 * This is deliberately the *same* schema for the admin composer and the
 * `POST /ingest/signals` endpoint an MT5 Expert Advisor calls. Wiring the
 * auto-feed later adds a caller, not a second definition of what a signal is.
 */
export const signalInputSchema = z
  .object({
    symbol: z.string().min(2).max(24),
    direction: z.enum(TRADE_DIRECTIONS),
    orderType: z.enum(ORDER_TYPES).default('MARKET'),
    entryLow: price,
    entryHigh: price,
    sl: price,
    tp1: price.nullish(),
    tp2: price.nullish(),
    tp3: price.nullish(),
    /** Price at which the stop should be pulled to break-even. */
    beTrigger: price.nullish(),
    /** Broker-specific pip size override; falls back to the instrument default. */
    pipSize: z.number().positive().nullish(),
    timeframe: z.string().max(12).default('H1'),
    riskPercent: z.number().min(0).max(100).nullish(),
    analysisText: z.string().max(4000).optional().default(''),
    /** Minimum plan tier that may see this signal. */
    minPlan: z.enum(PLAN_CODES).default('SIGNALS'),
    imageIds: z.array(z.string().uuid()).max(6).default([]),
    publishNow: z.boolean().default(false),
  })
  .refine((s) => s.entryLow <= s.entryHigh, {
    message: 'entryLow must be less than or equal to entryHigh',
    path: ['entryLow'],
  })
  .refine((s) => s.tp1 != null || s.tp2 != null || s.tp3 != null, {
    message: 'At least one take-profit target is required',
    path: ['tp1'],
  });
export type SignalInput = z.infer<typeof signalInputSchema>;

export const signalUpdateInputSchema = z.object({
  type: z.enum(SIGNAL_UPDATE_TYPES),
  note: z.string().max(1000).optional().default(''),
  /** Fill or exit price, used to compute the realised pip result. */
  price: price.nullish(),
  imageId: z.string().uuid().nullish(),
});
export type SignalUpdateInput = z.infer<typeof signalUpdateInputSchema>;

export const signalQuerySchema = z.object({
  symbol: z.string().optional(),
  direction: z.enum(TRADE_DIRECTIONS).optional(),
  status: z.string().optional(),
  openOnly: z.coerce.boolean().optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});
export type SignalQuery = z.infer<typeof signalQuerySchema>;

/* ------------------------------- auth ---------------------------------- */

export const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(2).max(60),
  locale: z.string().min(2).max(8).default('en'),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export const acceptDisclaimerSchema = z.object({
  /** Version of the risk disclaimer the user was shown, for the audit trail. */
  version: z.string().min(1).max(20),
});

/* ------------------------------ payments -------------------------------- */

export const checkoutSchema = z.object({
  planCode: z.enum(PLAN_CODES),
  provider: z.enum(PAYMENT_PROVIDERS),
  /** Where to send the user after an external checkout completes. */
  returnUrl: z.string().url().optional(),
});
export type CheckoutInput = z.infer<typeof checkoutSchema>;

export const manualPaymentProofSchema = z.object({
  paymentId: z.string().uuid(),
  /** Bank reference or on-chain transaction hash. */
  reference: z.string().min(3).max(200),
  proofImageId: z.string().uuid().nullish(),
});

export const paymentReviewSchema = z.object({
  approve: z.boolean(),
  note: z.string().max(500).optional().default(''),
});

/* ------------------------------ content --------------------------------- */

export const courseInputSchema = z.object({
  title: z.string().min(2).max(120),
  slug: z.string().min(2).max(140).regex(/^[a-z0-9-]+$/),
  description: z.string().max(4000).default(''),
  level: z.enum(['BEGINNER', 'INTERMEDIATE', 'ADVANCED']).default('BEGINNER'),
  minPlan: z.enum(PLAN_CODES).default('NORMAL'),
  coverImageId: z.string().uuid().nullish(),
  isPublished: z.boolean().default(false),
});

export const lessonInputSchema = z.object({
  courseId: z.string().uuid(),
  title: z.string().min(2).max(140),
  description: z.string().max(2000).default(''),
  /** Cloudflare Stream UID. Never sent to a client that lacks entitlement. */
  videoUid: z.string().min(4).max(64).nullish(),
  durationSec: z.number().int().min(0).default(0),
  order: z.number().int().min(0).default(0),
  isFreePreview: z.boolean().default(false),
});

/* ------------------------------ coaching -------------------------------- */

export const coachingBookingSchema = z.object({
  coachId: z.string().uuid().nullish(),
  scheduledAt: z.coerce.date(),
  durationMin: z.number().int().min(15).max(240).default(60),
  topic: z.string().max(500).default(''),
});

export const coachingStatusSchema = z.object({
  status: z.enum(COACHING_STATUSES),
  notes: z.string().max(4000).optional(),
});

/* -------------------------------- ads ----------------------------------- */

export const adPlacementSchema = z.object({
  slot: z.enum(AD_SLOTS),
  network: z.string().min(2).max(40).default('ADMOB'),
  unitIdIos: z.string().max(120).default(''),
  unitIdAndroid: z.string().max(120).default(''),
  isEnabled: z.boolean().default(true),
  /** Minimum seconds between two impressions of this slot. */
  minIntervalSec: z.number().int().min(0).default(60),
  /** Every listed plan sees this slot suppressed. Enforced server-side. */
  hideForPlans: z.array(z.enum(PLAN_CODES)).default(['PRO', 'ULTRA']),
});

/* -------------------------------- links --------------------------------- */

export const appLinkSchema = z.object({
  label: z.string().min(1).max(60),
  url: z.string().url(),
  icon: z.string().max(40).default('link'),
  category: z.enum(LINK_CATEGORIES).default('SOCIAL'),
  sortOrder: z.number().int().default(0),
  isActive: z.boolean().default(true),
});

/* -------------------------------- push ---------------------------------- */

export const deviceRegisterSchema = z.object({
  pushToken: z.string().min(10).max(200),
  platform: z.enum(['ios', 'android']),
  appVersion: z.string().max(20).default(''),
});

export const pushCampaignSchema = z.object({
  title: z.string().min(1).max(80),
  body: z.string().min(1).max(300),
  deepLink: z.string().max(200).optional().default(''),
  /** Empty means everyone; otherwise only holders of these tiers. */
  audiencePlans: z.array(z.enum(PLAN_CODES)).default([]),
  scheduledAt: z.coerce.date().nullish(),
});

/* ------------------------------ telegram -------------------------------- */

export const telegramBroadcastSchema = z.object({
  text: z.string().min(1).max(4000),
  audiencePlans: z.array(z.enum(PLAN_CODES)).default([]),
  imageId: z.string().uuid().nullish(),
});
