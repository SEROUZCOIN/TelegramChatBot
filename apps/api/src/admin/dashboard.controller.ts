import { Controller, Get, Query } from '@nestjs/common';
import { computeStats } from '@tsp/shared';
import { Roles } from '../common/decorators';
import { PrismaService } from '../common/prisma.service';

@Controller('admin/dashboard')
@Roles('ADMIN')
export class DashboardController {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * The numbers that tell you whether the business is working: recurring
   * revenue, who is subscribed to what, how the signals have actually
   * performed, and what is waiting on a human.
   */
  @Get()
  async overview(@Query('days') days = '30') {
    const window = Number(days) || 30;
    const since = new Date(Date.now() - window * 86_400_000);
    const now = new Date();

    const [subsByPlan, paidPayments, signals, pendingReview, newUsers, activeDevices, openSessions] =
      await Promise.all([
        this.prisma.subscription.groupBy({
          by: ['planId'],
          where: {
            status: 'ACTIVE',
            OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          },
          _count: { _all: true },
        }),
        this.prisma.payment.findMany({
          where: { status: 'PAID', updatedAt: { gte: since } },
          select: { amountCents: true, currency: true, provider: true, planId: true },
        }),
        this.prisma.signal.findMany({
          where: { publishedAt: { gte: since, not: null } },
          select: { status: true, resultPips: true, plannedRR: true, closedAt: true },
        }),
        this.prisma.payment.count({ where: { status: 'AWAITING_REVIEW' } }),
        this.prisma.user.count({ where: { createdAt: { gte: since }, deletedAt: null } }),
        this.prisma.device.count({ where: { lastSeenAt: { gte: new Date(Date.now() - 86_400_000) } } }),
        this.prisma.coachingSession.count({
          where: { status: { in: ['REQUESTED', 'SCHEDULED'] }, scheduledAt: { gte: now } },
        }),
      ]);

    const plans = await this.prisma.plan.findMany({
      select: { id: true, code: true, name: true, priceCents: true, interval: true },
    });
    const planById = new Map(plans.map((p) => [p.id, p]));

    // Monthly recurring revenue from live subscriptions, with annual plans
    // amortised. One-time coaching packages are excluded — counting a $5,000
    // one-off as recurring would badly overstate MRR.
    const mrrCents = subsByPlan.reduce((sum, row) => {
      const plan = planById.get(row.planId);
      if (!plan || plan.interval === 'ONE_TIME') return sum;
      const monthly = plan.interval === 'YEAR' ? plan.priceCents / 12 : plan.priceCents;
      return sum + monthly * row._count._all;
    }, 0);

    const revenueCents = paidPayments.reduce((s, p) => s + p.amountCents, 0);

    return {
      windowDays: window,
      revenue: {
        mrrCents: Math.round(mrrCents),
        windowRevenueCents: revenueCents,
        oneTimeCents: paidPayments
          .filter((p) => planById.get(p.planId)?.interval === 'ONE_TIME')
          .reduce((s, p) => s + p.amountCents, 0),
        byProvider: tally(paidPayments.map((p) => p.provider)),
      },
      subscribers: subsByPlan.map((row) => ({
        plan: planById.get(row.planId)?.code ?? 'UNKNOWN',
        count: row._count._all,
      })),
      signals: computeStats(signals),
      queue: { paymentsAwaitingReview: pendingReview, upcomingCoaching: openSessions },
      growth: { newUsers, activeDevices24h: activeDevices },
    };
  }

  @Get('audit')
  audit(@Query('take') take = '100') {
    return this.prisma.auditLog.findMany({
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(take) || 100, 500),
      include: { actor: { select: { id: true, email: true, displayName: true } } },
    });
  }
}

function tally(values: string[]): Record<string, number> {
  return values.reduce<Record<string, number>>((acc, v) => {
    acc[v] = (acc[v] ?? 0) + 1;
    return acc;
  }, {});
}
