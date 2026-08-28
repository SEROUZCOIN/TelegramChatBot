import type { PaymentProviderCode, Plan, User } from '@prisma/client';

/**
 * One rail for taking money.
 *
 * The platform runs on EXTERNAL rails by default (Stripe, crypto, bank), which
 * keeps roughly 97% of revenue instead of paying a 15–30% store commission. The
 * IAP provider is implemented and registered but stays inert unless a plan's
 * `paymentMode` allows it.
 *
 * That switch exists because Apple treats the tiers differently. Guideline
 * 3.1.3(d) explicitly permits outside payment for "real-time person-to-person
 * services between two individuals (for example tutoring students)", which
 * covers the PRO and ULTRA coaching tiers. Guideline 3.1.1 requires in-app
 * purchase to unlock digital content, which is what the NORMAL recorded-video
 * tier sells. If App Review objects to that one plan, flipping its
 * `paymentMode` to IAP swaps the rail with no code change and no new build.
 */
export interface CheckoutSession {
  /** Where to send the user. Null for rails settled out of band, like a bank transfer. */
  url: string | null;
  paymentId: string;
  provider: PaymentProviderCode;
  /** Shown in-app when there is no URL to open (bank details, wallet address). */
  instructions?: string;
  /** True when a human must approve before the entitlement is granted. */
  requiresManualReview?: boolean;
}

export interface PaymentProvider {
  readonly code: PaymentProviderCode;

  /** Whether this rail is configured well enough to be offered right now. */
  isAvailable(): boolean;

  createCheckout(input: {
    user: Pick<User, 'id' | 'email' | 'displayName'>;
    plan: Plan;
    paymentId: string;
    returnUrl?: string;
  }): Promise<CheckoutSession>;
}

export const PAYMENT_PROVIDERS_TOKEN = Symbol('PAYMENT_PROVIDERS');
