import { Body, Controller, Delete, Get, Param, Post, Put, Query } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { AuditService } from '../common/audit.service';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';

const profileSchema = z.object({
  displayName: z.string().min(2).max(60).optional(),
  locale: z.string().min(2).max(8).optional(),
});

const grantSchema = z.object({
  planCode: z.enum(['SIGNALS', 'NORMAL', 'PRO', 'ULTRA']),
  durationDays: z.number().int().min(1).max(3650).nullable(),
  reason: z.string().max(300).default(''),
});

@Controller('me')
export class UsersController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  @Get()
  async profile(@CurrentUser('id') userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        displayName: true,
        role: true,
        locale: true,
        avatarUrl: true,
        telegramUsername: true,
        telegramLinkCode: true,
        riskDisclaimerAcceptedAt: true,
        riskDisclaimerVersion: true,
        createdAt: true,
      },
    });
    return user;
  }

  @Put()
  update(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(profileSchema)) body: z.infer<typeof profileSchema>,
  ) {
    return this.prisma.user.update({
      where: { id: userId },
      data: body,
      select: { id: true, displayName: true, locale: true },
    });
  }

  /** Rotate the code used to bind a Telegram account to this user. */
  @Post('telegram/link-code')
  async linkCode(@CurrentUser('id') userId: string) {
    const code = randomBytes(6).toString('hex');
    await this.prisma.user.update({ where: { id: userId }, data: { telegramLinkCode: code } });
    return { code };
  }

  /**
   * In-app account deletion.
   *
   * Required by Apple guideline 5.1.1(v) for any app with account creation, and
   * its absence is a routine rejection. Personal data is scrubbed immediately
   * while the row is retained in tombstone form, because payment records have
   * to survive for accounting and chargeback disputes.
   */
  @Delete()
  async deleteAccount(@CurrentUser('id') userId: string) {
    const scrubbed = `deleted+${userId}@deleted.invalid`;

    await this.prisma.$transaction([
      this.prisma.device.deleteMany({ where: { userId } }),
      this.prisma.user.update({
        where: { id: userId },
        data: {
          email: scrubbed,
          displayName: 'Deleted user',
          passwordHash: randomBytes(32).toString('hex'),
          avatarUrl: null,
          telegramId: null,
          telegramUsername: null,
          telegramLinkCode: null,
          deletedAt: new Date(),
        },
      }),
      this.prisma.subscription.updateMany({
        where: { userId },
        data: { status: 'CANCELLED', cancelledAt: new Date() },
      }),
    ]);

    await this.audit.record({ actorId: userId, action: 'account.delete', entity: 'User', entityId: userId });
    return { deleted: true };
  }
}

@Controller('admin/users')
@Roles('ADMIN')
export class AdminUsersController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly audit: AuditService,
  ) {}

  @Get()
  async list(@Query('q') q?: string, @Query('take') take = '50') {
    return this.prisma.user.findMany({
      where: q
        ? {
            OR: [
              { email: { contains: q, mode: 'insensitive' } },
              { displayName: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {},
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(take) || 50, 200),
      select: {
        id: true,
        email: true,
        displayName: true,
        role: true,
        isBanned: true,
        deletedAt: true,
        createdAt: true,
        riskDisclaimerAcceptedAt: true,
        subscriptions: {
          where: { status: 'ACTIVE' },
          select: { expiresAt: true, plan: { select: { code: true } } },
        },
      },
    });
  }

  /**
   * Grant a plan by hand — for a bank transfer settled off-platform, a refund
   * make-good, or a comped account. Audited, since it hands out paid access.
   */
  @Post(':id/grant')
  async grant(
    @Param('id') userId: string,
    @CurrentUser('id') actorId: string,
    @Body(new ZodValidationPipe(grantSchema)) body: z.infer<typeof grantSchema>,
  ) {
    const plan = await this.prisma.plan.findUniqueOrThrow({ where: { code: body.planCode } });

    await this.entitlements.grant({
      userId,
      planId: plan.id,
      provider: 'BANK',
      durationDays: body.durationDays,
    });

    await this.audit.record({
      actorId,
      action: 'subscription.grant',
      entity: 'User',
      entityId: userId,
      after: { planCode: body.planCode, durationDays: body.durationDays, reason: body.reason },
    });

    return { granted: true };
  }

  @Post(':id/ban')
  async ban(
    @Param('id') userId: string,
    @CurrentUser('id') actorId: string,
    @Body() body: { banned: boolean },
  ) {
    await this.prisma.user.update({ where: { id: userId }, data: { isBanned: body.banned } });
    await this.audit.record({
      actorId,
      action: body.banned ? 'user.ban' : 'user.unban',
      entity: 'User',
      entityId: userId,
    });
    return { ok: true };
  }
}
