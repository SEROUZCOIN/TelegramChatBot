import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import type { PlanCode } from '@prisma/client';
import {
  checkoutSchema,
  manualPaymentProofSchema,
  paymentReviewSchema,
  type CheckoutInput,
} from '@tsp/shared';
import { z } from 'zod';
import { AuditService } from '../common/audit.service';
import { CurrentUser, Public, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { PaymentsService } from './payments.service';
import { StripeProvider } from './providers/stripe.provider';
import { CryptoProvider } from './providers/crypto.provider';

@Controller('payments')
export class PaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('providers')
  providers(@Query('plan') plan: string) {
    return this.payments.availableProviders(plan as PlanCode);
  }

  /**
   * Starts a checkout and returns a URL for the app to open.
   *
   * The app opens this in the system browser rather than an embedded webview:
   * an in-app webview around an external payment page is both a poor trust
   * signal for the buyer and the pattern app review treats most harshly.
   */
  @Post('checkout')
  checkout(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(checkoutSchema)) body: CheckoutInput,
  ) {
    return this.payments.createCheckout({
      userId,
      planCode: body.planCode as PlanCode,
      provider: body.provider,
      returnUrl: body.returnUrl,
    });
  }

  /** Submit a bank reference or on-chain transaction hash for manual review. */
  @Post('proof')
  async proof(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(manualPaymentProofSchema))
    body: z.infer<typeof manualPaymentProofSchema>,
  ) {
    const proofUrl = body.proofImageId
      ? (await this.prisma.mediaAsset.findUnique({ where: { id: body.proofImageId } }))?.url
      : null;

    await this.payments.submitProof({
      userId,
      paymentId: body.paymentId,
      reference: body.reference,
      proofUrl,
    });
    return { status: 'AWAITING_REVIEW' };
  }

  @Get('history')
  history(@CurrentUser('id') userId: string) {
    return this.payments.historyFor(userId);
  }
}

@Controller('webhooks')
export class PaymentWebhooksController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly stripe: StripeProvider,
    private readonly crypto: CryptoProvider,
  ) {}

  /**
   * Stripe is the authority on whether money moved, not the browser redirect —
   * a user can close the tab before returning, and a redirect can be forged.
   * The raw body is required here because the signature covers the exact bytes.
   */
  @Public()
  @Post('stripe')
  async stripeHook(
    @Req() req: { rawBody?: Buffer },
    @Headers('stripe-signature') signature: string,
  ) {
    if (!req.rawBody) throw new BadRequestException('Raw body unavailable');
    if (!signature) throw new BadRequestException('Missing stripe-signature');

    const event = this.stripe.constructEvent(req.rawBody, signature);

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as { id: string; metadata?: Record<string, string> };
      const paymentId = session.metadata?.paymentId;
      if (paymentId) await this.payments.settle(paymentId, session.id);
    }

    return { received: true };
  }

  @Public()
  @Post('crypto')
  async cryptoHook(
    @Req() req: { rawBody?: Buffer },
    @Headers('x-nowpayments-sig') signature: string,
  ) {
    if (!req.rawBody) throw new BadRequestException('Raw body unavailable');
    if (!this.crypto.verifyIpn(req.rawBody.toString('utf8'), signature ?? '')) {
      throw new BadRequestException('Invalid IPN signature');
    }

    const body = JSON.parse(req.rawBody.toString('utf8')) as {
      order_id?: string;
      payment_status?: string;
      payment_id?: string | number;
    };

    if (body.payment_status === 'finished' || body.payment_status === 'confirmed') {
      if (body.order_id) await this.payments.settle(body.order_id, String(body.payment_id ?? ''));
    }

    return { received: true };
  }

  /**
   * RevenueCat webhook, live only if a plan is ever switched to in-app purchase.
   * A purchase is never trusted from the device: the store validates the
   * receipt, RevenueCat relays it, and the entitlement is granted from here.
   */
  @Public()
  @Post('revenuecat')
  async revenueCatHook(
    @Req() req: { rawBody?: Buffer },
    @Headers('authorization') auth: string,
  ) {
    const expected = process.env.REVENUECAT_WEBHOOK_SECRET ?? '';
    if (!expected || auth !== `Bearer ${expected}`) {
      throw new BadRequestException('Invalid webhook authorization');
    }

    const body = JSON.parse(req.rawBody?.toString('utf8') ?? '{}') as {
      event?: { type?: string; app_user_id?: string; transaction_id?: string };
    };

    const type = body.event?.type;
    if (type === 'INITIAL_PURCHASE' || type === 'RENEWAL' || type === 'NON_RENEWING_PURCHASE') {
      // app_user_id is set to our payment id when the checkout is created.
      const paymentId = body.event?.app_user_id;
      if (paymentId) await this.payments.settle(paymentId, body.event?.transaction_id ?? null);
    }

    return { received: true };
  }
}

@Controller('admin/payments')
@Roles('ADMIN')
export class AdminPaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly audit: AuditService,
  ) {}

  @Get('pending')
  pending() {
    return this.payments.pendingReview();
  }

  @Post(':id/review')
  async review(
    @Param('id') id: string,
    @CurrentUser('id') reviewerId: string,
    @Body(new ZodValidationPipe(paymentReviewSchema))
    body: z.infer<typeof paymentReviewSchema>,
  ) {
    await this.payments.review({
      paymentId: id,
      reviewerId,
      approve: body.approve,
      note: body.note,
    });
    await this.audit.record({
      actorId: reviewerId,
      action: body.approve ? 'payment.approve' : 'payment.reject',
      entity: 'Payment',
      entityId: id,
      after: { note: body.note },
    });
    return { reviewed: true };
  }
}
