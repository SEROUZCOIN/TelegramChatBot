import { ForbiddenException, Injectable } from '@nestjs/common';
import { PlanCode } from '@prisma/client';
import { canAccessContent, resolveEntitlements, type Entitlements } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';

/**
 * The single place that answers "what is this user allowed to see".
 *
 * Every gated read goes through `assertCanAccess`. Nothing about access is
 * decided on the client: the app renders what it is given and asks again for
 * anything locked, so a patched binary gains nothing.
 */
@Injectable()
export class EntitlementsService {
  constructor(private readonly prisma: PrismaService) {}

  async forUser(userId: string): Promise<Entitlements> {
    const subs = await this.prisma.subscription.findMany({
      where: { userId },
      include: { plan: { select: { code: true } } },
    });

    return resolveEntitlements(
      subs.map((s) => ({
        planCode: s.plan.code as PlanCode,
        status: s.status,
        expiresAt: s.expiresAt,
      })),
    );
  }

  /** Anonymous callers see only what FREE sees. */
  async forOptionalUser(userId: string | null | undefined): Promise<Entitlements> {
    return userId ? this.forUser(userId) : resolveEntitlements([]);
  }

  async assertCanAccess(userId: string, minPlan: PlanCode): Promise<Entitlements> {
    const ent = await this.forUser(userId);
    if (!canAccessContent(ent.plan, minPlan)) {
      throw new ForbiddenException({
        message: 'Your plan does not include this content',
        requiredPlan: minPlan,
        currentPlan: ent.plan,
      });
    }
    return ent;
  }

  /**
   * Grants or extends a subscription after a payment settles.
   *
   * Renewals extend from the current expiry rather than from now, so a user who
   * renews early is not silently charged for days they already owned.
   */
  async grant(input: {
    userId: string;
    planId: string;
    provider: 'STRIPE' | 'CRYPTO' | 'BANK' | 'IAP';
    externalId?: string | null;
    durationDays: number | null;
  }): Promise<void> {
    const existing = await this.prisma.subscription.findFirst({
      where: { userId: input.userId, planId: input.planId },
      orderBy: { createdAt: 'desc' },
    });

    const now = new Date();
    const base =
      existing?.expiresAt && existing.expiresAt > now && existing.status === 'ACTIVE'
        ? existing.expiresAt
        : now;

    const expiresAt =
      input.durationDays === null
        ? null
        : new Date(base.getTime() + input.durationDays * 86_400_000);

    if (existing) {
      await this.prisma.subscription.update({
        where: { id: existing.id },
        data: {
          status: 'ACTIVE',
          expiresAt,
          provider: input.provider,
          externalId: input.externalId ?? existing.externalId,
          cancelledAt: null,
        },
      });
      return;
    }

    await this.prisma.subscription.create({
      data: {
        userId: input.userId,
        planId: input.planId,
        status: 'ACTIVE',
        startedAt: now,
        expiresAt,
        provider: input.provider,
        externalId: input.externalId ?? null,
      },
    });
  }
}
