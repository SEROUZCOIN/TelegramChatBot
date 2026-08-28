import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PaymentProviderCode, Plan, User } from '@prisma/client';
import type { AppConfig } from '../../config/configuration';
import type { CheckoutSession, PaymentProvider } from '../payment-provider.interface';

/**
 * Bank transfer, settled by hand.
 *
 * Worth keeping for the high-value tiers: a $5,000 coaching package is a
 * transfer many buyers would rather make from a bank than a card, and it costs
 * no processing fee at all. The user uploads proof, an admin approves it from
 * the review queue, and the entitlement is granted at approval — never before.
 */
@Injectable()
export class BankProvider implements PaymentProvider {
  readonly code: PaymentProviderCode = 'BANK';

  constructor(private readonly config: ConfigService<AppConfig, true>) {}

  isAvailable(): boolean {
    return Boolean(this.config.get('bank', { infer: true }).instructions);
  }

  async createCheckout(input: {
    user: Pick<User, 'id' | 'email' | 'displayName'>;
    plan: Plan;
    paymentId: string;
  }): Promise<CheckoutSession> {
    return {
      url: null,
      paymentId: input.paymentId,
      provider: this.code,
      requiresManualReview: true,
      instructions: this.config.get('bank', { infer: true }).instructions,
    };
  }
}
