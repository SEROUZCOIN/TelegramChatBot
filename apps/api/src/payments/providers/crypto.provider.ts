import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PaymentProviderCode, Plan, User } from '@prisma/client';
import { createHmac } from 'node:crypto';
import type { AppConfig } from '../../config/configuration';
import type { CheckoutSession, PaymentProvider } from '../payment-provider.interface';

/**
 * Crypto payment via NOWPayments.
 *
 * Falls back to a manual flow when no API key is configured: the user is told
 * to send funds and submit the transaction hash, and an admin approves it from
 * the review queue. That keeps the rail usable on day one without a merchant
 * account, and the approval path is the same one bank transfers use.
 */
@Injectable()
export class CryptoProvider implements PaymentProvider {
  readonly code: PaymentProviderCode = 'CRYPTO';
  private readonly logger = new Logger(CryptoProvider.name);

  constructor(private readonly config: ConfigService<AppConfig, true>) {}

  isAvailable(): boolean {
    return true; // manual fallback always works
  }

  private get apiKey(): string {
    return this.config.get('crypto', { infer: true }).apiKey;
  }

  async createCheckout(input: {
    user: Pick<User, 'id' | 'email' | 'displayName'>;
    plan: Plan;
    paymentId: string;
    returnUrl?: string;
  }): Promise<CheckoutSession> {
    if (!this.apiKey) {
      return {
        url: null,
        paymentId: input.paymentId,
        provider: this.code,
        requiresManualReview: true,
        instructions:
          'Send the exact amount to the wallet address shown in the app, then submit ' +
          'your transaction hash. Access is granted once the transfer is confirmed.',
      };
    }

    const res = await fetch('https://api.nowpayments.io/v1/invoice', {
      method: 'POST',
      headers: { 'x-api-key': this.apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({
        price_amount: input.plan.priceCents / 100,
        price_currency: input.plan.currency.toLowerCase(),
        order_id: input.paymentId,
        order_description: input.plan.name,
        success_url: input.returnUrl,
      }),
    });

    if (!res.ok) {
      this.logger.error(`NOWPayments invoice failed: ${res.status} ${await res.text()}`);
      return {
        url: null,
        paymentId: input.paymentId,
        provider: this.code,
        requiresManualReview: true,
        instructions: 'Crypto checkout is temporarily unavailable. Please contact support.',
      };
    }

    const invoice = (await res.json()) as { invoice_url?: string };
    return { url: invoice.invoice_url ?? null, paymentId: input.paymentId, provider: this.code };
  }

  /** Constant-time verification of the NOWPayments IPN signature. */
  verifyIpn(rawBody: string, signature: string): boolean {
    const secret = this.config.get('crypto', { infer: true }).ipnSecret;
    if (!secret) return false;

    // NOWPayments signs the JSON body with its keys sorted.
    const sorted = JSON.stringify(sortKeys(JSON.parse(rawBody) as Record<string, unknown>));
    const expected = createHmac('sha512', secret).update(sorted).digest('hex');
    return expected.length === signature.length && timingSafeEqualHex(expected, signature);
  }
}

function sortKeys(obj: Record<string, unknown>): Record<string, unknown> {
  return Object.keys(obj)
    .sort()
    .reduce<Record<string, unknown>>((acc, k) => {
      const v = obj[k];
      acc[k] = v && typeof v === 'object' && !Array.isArray(v)
        ? sortKeys(v as Record<string, unknown>)
        : v;
      return acc;
    }, {});
}

function timingSafeEqualHex(a: string, b: string): boolean {
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
