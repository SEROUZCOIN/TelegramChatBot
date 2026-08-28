import { PrismaClient } from '@prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { EntitlementsService } from '../src/entitlements/entitlements.service';
import { PrismaService } from '../src/common/prisma.service';

/**
 * Entitlement grants against a real database.
 *
 * These exercise the money-adjacent behaviour that unit tests with a fake
 * cannot: that a renewal extends rather than resets, and that a one-time
 * coaching purchase never lapses.
 */
describe('EntitlementsService', () => {
  const prisma = new PrismaClient() as PrismaService;
  let service: EntitlementsService;
  let userId: string;
  let monthlyPlanId: string;
  let oneTimePlanId: string;

  beforeAll(async () => {
    service = new EntitlementsService(prisma);

    const monthly = await prisma.plan.findUniqueOrThrow({ where: { code: 'SIGNALS' } });
    const oneTime = await prisma.plan.findUniqueOrThrow({ where: { code: 'ULTRA' } });
    monthlyPlanId = monthly.id;
    oneTimePlanId = oneTime.id;

    const user = await prisma.user.create({
      data: {
        email: `ent-${Date.now()}@test.invalid`,
        passwordHash: 'x',
        displayName: 'Entitlement Test',
      },
    });
    userId = user.id;
  });

  afterAll(async () => {
    await prisma.user.delete({ where: { id: userId } }).catch(() => undefined);
    await prisma.$disconnect();
  });

  it('starts a user with nothing', async () => {
    const ent = await service.forUser(userId);
    expect(ent.plan).toBe('FREE');
    expect(ent.canViewSignals).toBe(false);
    expect(ent.showAds).toBe(true);
  });

  it('grants a monthly plan and unlocks signals', async () => {
    await service.grant({
      userId,
      planId: monthlyPlanId,
      provider: 'STRIPE',
      durationDays: 30,
    });

    const ent = await service.forUser(userId);
    expect(ent.plan).toBe('SIGNALS');
    expect(ent.canViewSignals).toBe(true);
    expect(ent.canViewCourses).toBe(false);
    expect(ent.showAds).toBe(true);
  });

  it('extends an early renewal from the existing expiry, not from today', async () => {
    const before = await prisma.subscription.findFirstOrThrow({
      where: { userId, planId: monthlyPlanId },
    });

    await service.grant({
      userId,
      planId: monthlyPlanId,
      provider: 'STRIPE',
      durationDays: 30,
    });

    const after = await prisma.subscription.findFirstOrThrow({
      where: { userId, planId: monthlyPlanId },
    });

    // Charging someone for days they already owned would be a real refund
    // request, so the second 30 days stack on top of the first.
    const gainedDays =
      (after.expiresAt!.getTime() - before.expiresAt!.getTime()) / 86_400_000;
    expect(Math.round(gainedDays)).toBe(30);
  });

  it('treats a one-time coaching purchase as never expiring', async () => {
    await service.grant({
      userId,
      planId: oneTimePlanId,
      provider: 'BANK',
      durationDays: null,
    });

    const sub = await prisma.subscription.findFirstOrThrow({
      where: { userId, planId: oneTimePlanId },
    });
    expect(sub.expiresAt).toBeNull();

    const ent = await service.forUser(userId);
    expect(ent.plan).toBe('ULTRA');
    expect(ent.canAccessMentorship).toBe(true);
    // The tier that paid $5,000 must never see an ad.
    expect(ent.showAds).toBe(false);
  });

  it('refuses content above the held tier', async () => {
    const other = await prisma.user.create({
      data: {
        email: `deny-${Date.now()}@test.invalid`,
        passwordHash: 'x',
        displayName: 'Denied',
      },
    });

    await expect(service.assertCanAccess(other.id, 'NORMAL')).rejects.toThrow(
      /does not include/i,
    );

    await prisma.user.delete({ where: { id: other.id } });
  });

  it('ignores an expired subscription', async () => {
    const user = await prisma.user.create({
      data: {
        email: `expired-${Date.now()}@test.invalid`,
        passwordHash: 'x',
        displayName: 'Expired',
      },
    });

    await prisma.subscription.create({
      data: {
        userId: user.id,
        planId: monthlyPlanId,
        status: 'ACTIVE',
        expiresAt: new Date(Date.now() - 86_400_000),
      },
    });

    const ent = await service.forUser(user.id);
    expect(ent.plan).toBe('FREE');
    expect(ent.canViewSignals).toBe(false);

    await prisma.user.delete({ where: { id: user.id } });
  });
});
