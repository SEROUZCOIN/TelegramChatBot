import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Bot } from 'grammy';
import { STATUS_LABEL } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';
import type { AppConfig } from '../config/configuration';

/**
 * The subscriber-facing Telegram bot.
 *
 * It is a second front door onto the same account, not a separate product: a
 * user links their Telegram to their app account with a one-time code, and from
 * then on the bot answers with exactly what their plan entitles them to. Every
 * gated reply re-checks entitlements, so a lapsed subscription stops the DMs
 * without any separate bookkeeping.
 */
@Injectable()
export class TelegramBotService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelegramBotService.name);
  private bot: Bot | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {}

  async onModuleInit(): Promise<void> {
    const cfg = this.config.get('telegram', { infer: true });
    if (!cfg.botToken) {
      this.logger.warn('TELEGRAM_BOT_TOKEN unset — the subscriber bot will not start');
      return;
    }

    this.bot = new Bot(cfg.botToken);
    this.registerHandlers(this.bot);

    if (cfg.usePolling) {
      // start() resolves only when the bot stops, so it is intentionally not
      // awaited here — awaiting it would block application bootstrap forever.
      void this.bot.start({ onStart: () => this.logger.log('Telegram bot polling started') });
    } else {
      this.logger.log('Telegram bot running in webhook mode');
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.bot?.stop();
  }

  get instance(): Bot | null {
    return this.bot;
  }

  private registerHandlers(bot: Bot): void {
    bot.command('start', async (ctx) => {
      const code = ctx.match?.trim();
      const from = ctx.from;
      if (!from) return;

      if (!code) {
        await ctx.reply(
          'Welcome. To link this Telegram account to your subscription, open the app, ' +
            'go to Profile, tap "Connect Telegram", and send me the code shown there:\n\n' +
            '`/start YOUR-CODE`',
          { parse_mode: 'Markdown' },
        );
        return;
      }

      const user = await this.prisma.user.findUnique({ where: { telegramLinkCode: code } });
      if (!user) {
        await ctx.reply('That link code is not valid. Generate a fresh one in the app.');
        return;
      }

      // The code is single-use: it is cleared on redemption so a screenshot
      // shared later cannot bind someone else's Telegram to this account.
      await this.prisma.user.update({
        where: { id: user.id },
        data: {
          telegramId: BigInt(from.id),
          telegramUsername: from.username ?? null,
          telegramLinkCode: null,
        },
      });

      const ent = await this.entitlements.forUser(user.id);
      await ctx.reply(
        `Linked to ${user.displayName}. Your plan: *${ent.plan}*.\n\n` +
          'You will now receive signals here as they are published.',
        { parse_mode: 'Markdown' },
      );
    });

    bot.command('status', async (ctx) => {
      const user = await this.userFor(ctx.from?.id);
      if (!user) return void ctx.reply('This Telegram account is not linked yet. Send /start.');

      const ent = await this.entitlements.forUser(user.id);
      const expiry = ent.expiresAt
        ? `Renews or expires: ${ent.expiresAt.toISOString().slice(0, 10)}`
        : 'Lifetime access';

      await ctx.reply(`Plan: *${ent.plan}*\n${expiry}`, { parse_mode: 'Markdown' });
    });

    bot.command('signals', async (ctx) => {
      const user = await this.userFor(ctx.from?.id);
      if (!user) return void ctx.reply('Link your account first with /start.');

      const ent = await this.entitlements.forUser(user.id);
      if (!ent.canViewSignals) {
        await ctx.reply(
          'Live signals are part of the Signals plan and above. Open the app to upgrade.',
        );
        return;
      }

      const open = await this.prisma.signal.findMany({
        where: {
          publishedAt: { not: null },
          status: { in: ['PUBLISHED', 'ACTIVE', 'BE_SET', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT'] },
        },
        orderBy: { publishedAt: 'desc' },
        take: 10,
      });

      if (!open.length) return void ctx.reply('No open signals right now.');

      const lines = open.map(
        (s) => `• *${s.symbol}* ${s.direction} — ${STATUS_LABEL[s.status as never]}`,
      );
      await ctx.reply(`Open signals:\n\n${lines.join('\n')}`, { parse_mode: 'Markdown' });
    });

    bot.command('stats', async (ctx) => {
      const since = new Date(Date.now() - 30 * 86_400_000);
      const [wins, losses, be] = await Promise.all([
        this.prisma.signal.count({ where: { status: 'CLOSED_WIN', closedAt: { gte: since } } }),
        this.prisma.signal.count({ where: { status: 'CLOSED_LOSS', closedAt: { gte: since } } }),
        this.prisma.signal.count({ where: { status: 'CLOSED_BE', closedAt: { gte: since } } }),
      ]);

      const decided = wins + losses;
      const rate = decided ? ((wins / decided) * 100).toFixed(1) : '—';

      await ctx.reply(
        `*Last 30 days*\nWins: ${wins}\nLosses: ${losses}\nBreak-even: ${be}\nWin rate: ${rate}%\n\n` +
          '_Past performance does not indicate future results._',
        { parse_mode: 'Markdown' },
      );
    });

    bot.command('help', async (ctx) => {
      await ctx.reply(
        '/start <code> — link your app account\n' +
          '/status — your current plan\n' +
          '/signals — open signals\n' +
          '/stats — 30-day record\n\n' +
          'Educational content only. Not financial advice.',
      );
    });

    bot.catch((err) => this.logger.error('Telegram bot error', err.error as Error));
  }

  private async userFor(telegramId: number | undefined) {
    if (!telegramId) return null;
    return this.prisma.user.findFirst({
      where: { telegramId: BigInt(telegramId), isBanned: false, deletedAt: null },
    });
  }
}
