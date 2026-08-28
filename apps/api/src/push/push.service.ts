import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PlanCode } from '@prisma/client';
import { Expo, type ExpoPushMessage } from 'expo-server-sdk';
import { PLAN_RANK } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import type { AppConfig } from '../config/configuration';

@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private readonly expo: Expo;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {
    this.expo = new Expo({
      accessToken: this.config.get('expo', { infer: true }).accessToken || undefined,
    });
  }

  async registerDevice(userId: string, token: string, platform: string, appVersion: string) {
    if (!Expo.isExpoPushToken(token)) {
      this.logger.warn(`Rejected malformed push token from user ${userId}`);
      return null;
    }

    // A token can move between accounts on a shared device, so it is keyed on
    // the token and reassigned rather than duplicated.
    return this.prisma.device.upsert({
      where: { pushToken: token },
      create: { userId, pushToken: token, platform, appVersion },
      update: { userId, platform, appVersion, lastSeenAt: new Date() },
    });
  }

  /**
   * Notify everyone entitled to a signal.
   *
   * The audience is resolved from live subscriptions, so a lapsed subscriber
   * stops getting alerts the moment their plan expires without any extra
   * bookkeeping.
   */
  async sendToPlans(input: {
    title: string;
    body: string;
    deepLink?: string;
    minPlan: PlanCode;
  }): Promise<{ sent: number; failed: number }> {
    const eligible = Object.entries(PLAN_RANK)
      .filter(([, rank]) => rank >= PLAN_RANK[input.minPlan])
      .map(([code]) => code as PlanCode);

    const devices = await this.prisma.device.findMany({
      where: {
        user: {
          isBanned: false,
          deletedAt: null,
          subscriptions: {
            some: {
              status: 'ACTIVE',
              plan: { code: { in: eligible } },
              OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
            },
          },
        },
      },
      select: { pushToken: true },
    });

    return this.dispatch(
      devices.map((d) => d.pushToken),
      input,
    );
  }

  async sendCampaign(campaignId: string): Promise<{ sent: number; failed: number }> {
    const campaign = await this.prisma.pushCampaign.findUnique({ where: { id: campaignId } });
    if (!campaign) return { sent: 0, failed: 0 };

    const devices = await this.prisma.device.findMany({
      where: {
        user: {
          isBanned: false,
          deletedAt: null,
          ...(campaign.audiencePlans.length
            ? {
                subscriptions: {
                  some: {
                    status: 'ACTIVE',
                    plan: { code: { in: campaign.audiencePlans } },
                    OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
                  },
                },
              }
            : {}),
        },
      },
      select: { pushToken: true },
    });

    const result = await this.dispatch(devices.map((d) => d.pushToken), {
      title: campaign.title,
      body: campaign.body,
      deepLink: campaign.deepLink,
    });

    await this.prisma.pushCampaign.update({
      where: { id: campaignId },
      data: { sentAt: new Date(), sentCount: result.sent, failedCount: result.failed },
    });

    return result;
  }

  private async dispatch(
    tokens: string[],
    payload: { title: string; body: string; deepLink?: string },
  ): Promise<{ sent: number; failed: number }> {
    const valid = tokens.filter((t) => Expo.isExpoPushToken(t));
    if (!valid.length) return { sent: 0, failed: 0 };

    const messages: ExpoPushMessage[] = valid.map((to) => ({
      to,
      sound: 'default',
      title: payload.title,
      body: payload.body,
      data: payload.deepLink ? { deepLink: payload.deepLink } : {},
      priority: 'high',
    }));

    let sent = 0;
    let failed = 0;
    const dead: string[] = [];

    for (const chunk of this.expo.chunkPushNotifications(messages)) {
      try {
        const tickets = await this.expo.sendPushNotificationsAsync(chunk);
        tickets.forEach((ticket, i) => {
          if (ticket.status === 'ok') {
            sent += 1;
            return;
          }
          failed += 1;
          // Expo tells us when a token is permanently dead; pruning keeps the
          // device table from filling with uninstalled apps.
          if (ticket.details?.error === 'DeviceNotRegistered') {
            dead.push(chunk[i].to as string);
          }
        });
      } catch (err) {
        failed += chunk.length;
        this.logger.error('Push chunk failed', err as Error);
      }
    }

    if (dead.length) {
      await this.prisma.device.deleteMany({ where: { pushToken: { in: dead } } });
      this.logger.log(`Pruned ${dead.length} unregistered push tokens`);
    }

    return { sent, failed };
  }
}
