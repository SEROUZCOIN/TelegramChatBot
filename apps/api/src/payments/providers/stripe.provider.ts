import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PaymentProviderCode, Plan, User } from '@prisma/client';
import Stripe from 'stripe';
import type { AppConfig } from '../../config/configuration';
import type { CheckoutSession, PaymentProvider } from '../payment-provider.interface';

@Injectable()
export class StripeProvider implements PaymentProvider {
  readonly code: PaymentProviderCode = 'STRIPE';
  private readonly logger = new Logger(StripeProvider.name);
  private readonly client: Stripe | null;

  constructor(private readonly config: ConfigService<AppConfig, true>) {
    const key = this.config.get('stripe', { infer: true }).secretKey;
    this.client = key ? new Stripe(key, { apiVersion: '2025-02-24.acacia' }) : null;
    if (!this.client) {
      this.logger.warn('STRIPE_SECRET_KEY is unset — card checkout will not be offered');
    }
  }

  isAvailable(): boolean {
    return this.client !== null;
  }

  async createCheckout(input: {
    user: Pick<User, 'id' | 'email' | 'displayName'>;
    plan: Plan;
    paymentId: string;
    returnUrl?: string;
  }): Promise<CheckoutSession> {
    if (!this.client) throw new ServiceUnavailableException('Card payment is not configured');

    const cfg = this.config.get('stripe', { infer: true });
    const recurring = input.plan.interval !== 'ONE_TIME';

    const session = await this.client.checkout.sessions.create({
      mode: recurring ? 'subscription' : 'payment',
      customer_email: input.user.email,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: input.plan.currency.toLowerCase(),
            unit_amount: input.plan.priceCents,
            product_data: { name: input.plan.name, description: input.plan.tagline || undefined },
            ...(recurring
              ? { recurring: { interval: input.plan.interval === 'YEAR' ? 'year' : 'month' } }
              : {}),
          },
        },
      ],
      // The webhook, not the browser redirect, is what grants access — the user
      // can close the tab before returning, and a redirect can be forged.
      metadata: { paymentId: input.paymentId, userId: input.user.id, planId: input.plan.id },
      success_url: input.returnUrl ?? cfg.successUrl,
      cancel_url: cfg.cancelUrl,
    });

    return { url: session.url, paymentId: input.paymentId, provider: this.code };
  }

  /** Verifies the Stripe signature over the raw body. */
  constructEvent(rawBody: Buffer, signature: string): Stripe.Event {
    if (!this.client) throw new ServiceUnavailableException('Stripe is not configured');
    const secret = this.config.get('stripe', { infer: true }).webhookSecret;
    return this.client.webhooks.constructEvent(rawBody, signature, secret);
  }
}
