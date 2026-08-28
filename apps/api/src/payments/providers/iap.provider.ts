import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PaymentProviderCode, Plan, User } from '@prisma/client';
import type { AppConfig } from '../../config/configuration';
import type { CheckoutSession, PaymentProvider } from '../payment-provider.interface';

/**
 * In-app purchase, brokered by RevenueCat.
 *
 * Built and registered but inert: no plan ships with `paymentMode` allowing
 * IAP, so this provider is never selected. It exists as a switch rather than a
 * rewrite.
 *
 * The scenario it covers: Apple guideline 3.1.1 requires in-app purchase to
 * unlock digital content, and the NORMAL tier sells recorded video. If App
 * Review rejects that plan for taking payment outside the store, setting that
 * one plan's `paymentMode` to IAP (or BOTH) routes it here — one database row,
 * no code change, no second build in the review queue.
 *
 * Purchases are never trusted from the device. The client completes the
 * purchase through StoreKit / Play Billing, RevenueCat validates the receipt
 * server-side, and the entitlement is granted from RevenueCat's signed webhook.
 */
@Injectable()
export class IapProvider implements PaymentProvider {
  readonly code: PaymentProviderCode = 'IAP';
  private readonly logger = new Logger(IapProvider.name);

  constructor(private readonly config: ConfigService<AppConfig, true>) {}

  isAvailable(): boolean {
    return Boolean(this.config.get('revenueCat', { infer: true }).apiKey);
  }

  async createCheckout(input: {
    user: Pick<User, 'id' | 'email' | 'displayName'>;
    plan: Plan;
    paymentId: string;
  }): Promise<CheckoutSession> {
    // There is no URL to open: the purchase happens in the native store sheet.
    // The API's job is to hand back the product identifier and wait for the
    // webhook that confirms the store actually charged the user.
    const productId = input.plan.iapProductIdIos ?? input.plan.iapProductIdAndroid ?? '';
    if (!productId) {
      this.logger.error(`Plan ${input.plan.code} is set to IAP but has no product id configured`);
    }

    return {
      url: null,
      paymentId: input.paymentId,
      provider: this.code,
      instructions: productId,
    };
  }
}
