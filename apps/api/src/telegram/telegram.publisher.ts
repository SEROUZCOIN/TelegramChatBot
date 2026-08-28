import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PlanCode } from '@prisma/client';
import { Bot, GrammyError } from 'grammy';
import { canAccessContent, formatSignalMarkdown, PLAN_RANK } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import type { AppConfig } from '../config/configuration';

/**
 * Publishes signals to Telegram.
 *
 * The defining behaviour: when a trade progresses, the *original* message is
 * edited rather than a new one posted. A channel therefore reads as one live
 * thread per trade — entry, break-even, TP1, close, all in place — instead of a
 * wall of fragments a reader has to reassemble. The message ids that make that
 * possible live in the TelegramMessage table.
 */
@Injectable()
export class TelegramPublisher {
  private readonly logger = new Logger(TelegramPublisher.name);
  private bot: Bot | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {
    const token = this.config.get('telegram', { infer: true }).botToken;
    this.bot = token ? new Bot(token) : null;
    if (!this.bot) this.logger.warn('TELEGRAM_BOT_TOKEN unset — Telegram publishing is disabled');
  }

  get api() {
    return this.bot?.api ?? null;
  }

  async publishSignal(signalId: string): Promise<void> {
    if (!this.bot) return;

    const signal = await this.prisma.signal.findUnique({
      where: { id: signalId },
      include: { images: true, updates: { orderBy: { createdAt: 'asc' } } },
    });
    if (!signal || !signal.publishedAt) return;

    const targets = await this.audienceChats(signal.minPlan);
    const image = signal.images[0]?.brandedUrl ?? signal.images[0]?.url ?? null;

    for (const target of targets) {
      const text = formatSignalMarkdown(this.toCard(signal), { locked: target.locked });

      try {
        const sent = image
          ? await this.bot.api.sendPhoto(target.chatId, image, {
              caption: text,
              parse_mode: 'Markdown',
            })
          : await this.bot.api.sendMessage(target.chatId, text, { parse_mode: 'Markdown' });

        await this.prisma.telegramMessage.upsert({
          where: { signalId_chatId: { signalId, chatId: BigInt(target.chatId) } },
          create: {
            signalId,
            chatId: BigInt(target.chatId),
            messageId: sent.message_id,
            locked: target.locked,
          },
          update: { messageId: sent.message_id, locked: target.locked },
        });
      } catch (err) {
        this.logFailure(target.chatId, err);
      }
    }
  }

  /** Edit every copy of a signal in place so each trade stays one thread. */
  async updateSignal(signalId: string): Promise<void> {
    if (!this.bot) return;

    const signal = await this.prisma.signal.findUnique({
      where: { id: signalId },
      include: { images: true, updates: { orderBy: { createdAt: 'asc' } } },
    });
    if (!signal) return;

    const messages = await this.prisma.telegramMessage.findMany({ where: { signalId } });
    const hasImage = signal.images.length > 0;

    for (const msg of messages) {
      const text = formatSignalMarkdown(this.toCard(signal), { locked: msg.locked });
      const chatId = Number(msg.chatId);

      try {
        if (hasImage) {
          await this.bot.api.editMessageCaption(chatId, msg.messageId, {
            caption: text,
            parse_mode: 'Markdown',
          });
        } else {
          await this.bot.api.editMessageText(chatId, msg.messageId, text, {
            parse_mode: 'Markdown',
          });
        }
      } catch (err) {
        // Telegram rejects an edit that would not change anything. That is not
        // a failure worth logging as one.
        if (err instanceof GrammyError && err.description.includes('message is not modified')) {
          continue;
        }
        this.logFailure(chatId, err);
      }
    }
  }

  async broadcast(text: string, audiencePlans: PlanCode[], imageUrl?: string | null) {
    if (!this.bot) return { sent: 0 };

    const chats = await this.subscriberChats(audiencePlans);
    let sent = 0;

    for (const chatId of chats) {
      try {
        if (imageUrl) {
          await this.bot.api.sendPhoto(chatId, imageUrl, { caption: text, parse_mode: 'Markdown' });
        } else {
          await this.bot.api.sendMessage(chatId, text, { parse_mode: 'Markdown' });
        }
        sent += 1;
      } catch (err) {
        this.logFailure(chatId, err);
      }
    }

    return { sent };
  }

  /**
   * Who receives a signal, and in what form.
   *
   * Entitled subscribers get it in full by direct message. The public channel
   * gets a locked teaser — symbol and direction visible, levels withheld —
   * which is the funnel: it proves the call was timely without giving away what
   * subscribers pay for.
   */
  private async audienceChats(
    minPlan: PlanCode,
  ): Promise<Array<{ chatId: number; locked: boolean }>> {
    const targets: Array<{ chatId: number; locked: boolean }> = [];

    const channelId = this.config.get('telegram', { infer: true }).publicChannelId;
    if (channelId) targets.push({ chatId: Number(channelId), locked: true });

    const eligible = Object.entries(PLAN_RANK)
      .filter(([, rank]) => rank >= PLAN_RANK[minPlan])
      .map(([code]) => code as PlanCode);

    const linked = await this.prisma.user.findMany({
      where: {
        telegramId: { not: null },
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
      select: { telegramId: true },
    });

    for (const u of linked) {
      if (u.telegramId) targets.push({ chatId: Number(u.telegramId), locked: false });
    }

    return targets;
  }

  private async subscriberChats(plans: PlanCode[]): Promise<number[]> {
    const users = await this.prisma.user.findMany({
      where: {
        telegramId: { not: null },
        isBanned: false,
        deletedAt: null,
        ...(plans.length
          ? {
              subscriptions: {
                some: {
                  status: 'ACTIVE',
                  plan: { code: { in: plans } },
                  OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
                },
              },
            }
          : {}),
      },
      select: { telegramId: true },
    });

    return users.flatMap((u) => (u.telegramId ? [Number(u.telegramId)] : []));
  }

  private toCard(signal: {
    symbol: string;
    direction: 'BUY' | 'SELL';
    entryLow: number;
    entryHigh: number;
    sl: number;
    tp1: number | null;
    tp2: number | null;
    tp3: number | null;
    beTrigger: number | null;
    pipSize: number | null;
    timeframe: string;
    status: string;
    analysisText: string;
  }) {
    return {
      symbol: signal.symbol,
      direction: signal.direction,
      entryLow: signal.entryLow,
      entryHigh: signal.entryHigh,
      sl: signal.sl,
      tp1: signal.tp1,
      tp2: signal.tp2,
      tp3: signal.tp3,
      beTrigger: signal.beTrigger,
      pipSize: signal.pipSize,
      timeframe: signal.timeframe,
      status: signal.status as never,
      analysisText: signal.analysisText,
    };
  }

  private logFailure(chatId: number, err: unknown): void {
    if (err instanceof GrammyError && (err.error_code === 403 || err.error_code === 400)) {
      // The user blocked the bot or deleted the chat — expected, not an incident.
      this.logger.debug(`Telegram chat ${chatId} unreachable: ${err.description}`);
      return;
    }
    this.logger.error(`Telegram delivery to ${chatId} failed`, err as Error);
  }
}
