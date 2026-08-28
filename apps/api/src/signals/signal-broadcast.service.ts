import { Injectable, Logger } from '@nestjs/common';
import type { SignalUpdateType } from '@prisma/client';
import { UPDATE_LABEL } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import { PushService } from '../push/push.service';
import { TelegramPublisher } from '../telegram/telegram.publisher';

/**
 * Fans a signal event out to every channel at once.
 *
 * Kept apart from SignalsService so that a Telegram outage or an expired push
 * credential can never roll back the database write that already succeeded —
 * the trade record is the thing that must not be lost.
 */
@Injectable()
export class SignalBroadcastService {
  private readonly logger = new Logger(SignalBroadcastService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly push: PushService,
    private readonly telegram: TelegramPublisher,
  ) {}

  async onPublished(signalId: string): Promise<void> {
    const signal = await this.prisma.signal.findUnique({ where: { id: signalId } });
    if (!signal) return;

    await this.settle([
      this.push.sendToPlans({
        title: `${signal.direction} ${signal.symbol}`,
        body: 'New signal published. Tap to see entry, targets and stop.',
        deepLink: `/signals/${signal.id}`,
        minPlan: signal.minPlan,
      }),
      this.telegram.publishSignal(signalId),
    ]);
  }

  async onUpdated(signalId: string, type: SignalUpdateType): Promise<void> {
    const signal = await this.prisma.signal.findUnique({ where: { id: signalId } });
    if (!signal) return;

    await this.settle([
      this.push.sendToPlans({
        title: `${signal.symbol} — ${UPDATE_LABEL[type]}`,
        body: `The ${signal.direction} setup has moved. Open for the full timeline.`,
        deepLink: `/signals/${signal.id}`,
        minPlan: signal.minPlan,
      }),
      // Edits the original message rather than posting a new one.
      this.telegram.updateSignal(signalId),
    ]);
  }

  /** Run every channel, log what failed, and never throw. */
  private async settle(work: Promise<unknown>[]): Promise<void> {
    const results = await Promise.allSettled(work);
    for (const r of results) {
      if (r.status === 'rejected') {
        this.logger.error('Signal broadcast channel failed', r.reason as Error);
      }
    }
  }
}
