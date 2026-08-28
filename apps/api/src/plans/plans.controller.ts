import { Body, Controller, Get, Param, Put } from '@nestjs/common';
import { z } from 'zod';
import { PLAN_CODES, PAYMENT_MODES } from '@tsp/shared';
import { AuditService } from '../common/audit.service';
import { CurrentUser, Public, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { PaymentsService } from '../payments/payments.service';

const planUpdateSchema = z.object({
  name: z.string().min(2).max(80).optional(),
  tagline: z.string().max(200).optional(),
  priceCents: z.number().int().min(0).optional(),
  currency: z.string().length(3).optional(),
  features: z.array(z.string()).optional(),
  isActive: z.boolean().optional(),
  sortOrder: z.number().int().optional(),
  paymentMode: z.enum(PAYMENT_MODES).optional(),
  iapProductIdIos: z.string().max(120).nullish(),
  iapProductIdAndroid: z.string().max(120).nullish(),
});

@Controller('plans')
export class PlansController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly payments: PaymentsService,
  ) {}

  /**
   * The pricing screen. Public so the paywall renders before sign-up.
   *
   * Each plan reports the rails it accepts, which is what lets the app show a
   * card button, a crypto button, or a native store sheet without knowing the
   * policy reasoning behind the choice.
   */
  @Public()
  @Get()
  async list() {
    const plans = await this.prisma.plan.findMany({
      where: { isActive: true },
      orderBy: { sortOrder: 'asc' },
    });

    return Promise.all(
      plans.map(async (p) => ({
        code: p.code,
        name: p.name,
        tagline: p.tagline,
        priceCents: p.priceCents,
        currency: p.currency,
        interval: p.interval,
        features: p.features,
        providers: await this.payments.availableProviders(p.code),
      })),
    );
  }
}

@Controller('admin/plans')
@Roles('ADMIN')
export class AdminPlansController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  @Get()
  list() {
    return this.prisma.plan.findMany({ orderBy: { sortOrder: 'asc' } });
  }

  /**
   * Edit a plan, including its payment rails.
   *
   * `paymentMode` is the switch that matters: setting the recorded-video plan
   * to IAP moves it onto in-app purchase without a code change or a new build,
   * which is the prepared answer if App Review objects to it selling digital
   * content through an external checkout. Every change is audited because it
   * moves money.
   */
  @Put(':code')
  async update(
    @Param('code') code: string,
    @CurrentUser('id') actorId: string,
    @Body(new ZodValidationPipe(planUpdateSchema)) body: z.infer<typeof planUpdateSchema>,
  ) {
    const parsed = PLAN_CODES.includes(code as never) ? (code as (typeof PLAN_CODES)[number]) : null;
    if (!parsed) throw new Error(`Unknown plan code ${code}`);

    const before = await this.prisma.plan.findUnique({ where: { code: parsed } });
    const after = await this.prisma.plan.update({
      where: { code: parsed },
      data: { ...body, features: body.features as never },
    });

    await this.audit.record({
      actorId,
      action: 'plan.update',
      entity: 'Plan',
      entityId: after.id,
      before: { priceCents: before?.priceCents, paymentMode: before?.paymentMode },
      after: { priceCents: after.priceCents, paymentMode: after.paymentMode },
    });

    return after;
  }
}
