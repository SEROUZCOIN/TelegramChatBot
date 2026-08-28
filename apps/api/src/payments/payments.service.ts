import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import type { PaymentProviderCode, PlanCode } from '@prisma/client';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';
import {
  PAYMENT_PROVIDERS_TOKEN,
  type CheckoutSession,
  type PaymentProvider,
} from './payment-provider.interface';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    @Inject(PAYMENT_PROVIDERS_TOKEN) private readonly providers: PaymentProvider[],
  ) {}

  private provider(code: PaymentProviderCode): PaymentProvider {
    const p = this.providers.find((x) => x.code === code);
    if (!p) throw new BadRequestException(`Unknown payment provider ${code}`);
    return p;
  }

  /**
   * Which rails a given plan may be bought through right now.
   *
   * A plan's `paymentMode` decides whether external rails, in-app purchase, or
   * both are permitted; a provider also has to be configured to appear.
   */
  async availableProviders(planCode: PlanCode): Promise<PaymentProviderCode[]> {
    const plan = await this.prisma.plan.findUnique({ where: { code: planCode } });
    if (!plan) throw new NotFoundException('Plan not found');

    const externalAllowed = plan.paymentMode === 'EXTERNAL' || plan.paymentMode === 'BOTH';
    const iapAllowed = plan.paymentMode === 'IAP' || plan.paymentMode === 'BOTH';

    return this.providers
      .filter((p) => (p.code === 'IAP' ? iapAllowed : externalAllowed))
      .filter((p) => p.isAvailable())
      .map((p) => p.code);
  }

  async createCheckout(input: {
    userId: string;
    planCode: PlanCode;
    provider: PaymentProviderCode;
    returnUrl?: string;
  }): Promise<CheckoutSession> {
    const [user, plan] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: input.userId } }),
      this.prisma.plan.findUnique({ where: { code: input.planCode } }),
    ]);

    if (!user) throw new NotFoundException('User not found');
    if (!plan || !plan.isActive) throw new NotFoundException('Plan not available');

    const allowed = await this.availableProviders(input.planCode);
    if (!allowed.includes(input.provider)) {
      throw new BadRequestException(
        `${input.provider} is not accepted for the ${plan.name} plan`,
      );
    }

    // The payment row is created first so the webhook has something to settle
    // against even if the user abandons checkout.
    const payment = await this.prisma.payment.create({
      data: {
        userId: user.id,
        planId: plan.id,
        provider: input.provider,
        status: 'PENDING',
        amountCents: plan.priceCents,
        currency: plan.currency,
      },
    });

    const session = await this.provider(input.provider).createCheckout({
      user,
      plan,
      paymentId: payment.id,
      returnUrl: input.returnUrl,
    });

    if (session.requiresManualReview) {
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { status: 'AWAITING_REVIEW' },
      });
    }

    return session;
  }

  /**
   * Settle a payment and grant the entitlement.
   *
   * Idempotent: webhooks retry, and a provider that delivers the same event
   * three times must not extend a subscription three times.
   */
  async settle(paymentId: string, providerRef?: string | null): Promise<void> {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: { plan: true },
    });
    if (!payment) {
      this.logger.warn(`Webhook referenced unknown payment ${paymentId}`);
      return;
    }
    if (payment.status === 'PAID') {
      this.logger.log(`Payment ${paymentId} already settled — ignoring duplicate webhook`);
      return;
    }

    await this.prisma.payment.update({
      where: { id: paymentId },
      data: { status: 'PAID', providerRef: providerRef ?? payment.providerRef },
    });

    await this.entitlements.grant({
      userId: payment.userId,
      planId: payment.planId,
      provider: payment.provider,
      externalId: providerRef ?? null,
      durationDays: durationFor(payment.plan.interval),
    });

    this.logger.log(`Settled ${payment.provider} payment ${paymentId} for ${payment.plan.code}`);
  }

  async submitProof(input: {
    userId: string;
    paymentId: string;
    reference: string;
    proofUrl?: string | null;
  }): Promise<void> {
    const payment = await this.prisma.payment.findUnique({ where: { id: input.paymentId } });
    if (!payment || payment.userId !== input.userId) throw new NotFoundException('Payment not found');
    if (payment.status === 'PAID') throw new BadRequestException('This payment is already settled');

    await this.prisma.payment.update({
      where: { id: input.paymentId },
      data: {
        status: 'AWAITING_REVIEW',
        reference: input.reference,
        proofUrl: input.proofUrl ?? payment.proofUrl,
      },
    });
  }

  /** The admin approval queue for bank transfers and manual crypto payments. */
  async pendingReview() {
    return this.prisma.payment.findMany({
      where: { status: 'AWAITING_REVIEW' },
      include: {
        plan: { select: { code: true, name: true } },
        user: { select: { id: true, email: true, displayName: true } },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  async review(input: {
    paymentId: string;
    reviewerId: string;
    approve: boolean;
    note: string;
  }): Promise<void> {
    const payment = await this.prisma.payment.findUnique({ where: { id: input.paymentId } });
    if (!payment) throw new NotFoundException('Payment not found');
    if (payment.status === 'PAID') throw new BadRequestException('Already approved');

    if (!input.approve) {
      await this.prisma.payment.update({
        where: { id: input.paymentId },
        data: {
          status: 'FAILED',
          reviewedById: input.reviewerId,
          reviewedAt: new Date(),
          reviewNote: input.note,
        },
      });
      return;
    }

    await this.prisma.payment.update({
      where: { id: input.paymentId },
      data: { reviewedById: input.reviewerId, reviewedAt: new Date(), reviewNote: input.note },
    });
    await this.settle(input.paymentId, payment.reference);
  }

  async historyFor(userId: string) {
    return this.prisma.payment.findMany({
      where: { userId },
      include: { plan: { select: { code: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }
}

/** Null means a one-time purchase that never lapses. */
function durationFor(interval: string): number | null {
  if (interval === 'MONTH') return 30;
  if (interval === 'YEAR') return 365;
  return null;
}
