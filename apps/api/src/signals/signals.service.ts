import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PlanCode, Prisma, SignalStatus, SignalUpdateType } from '@prisma/client';
import {
  canAccessContent,
  canApplyUpdate,
  computeSignalMetrics,
  computeStats,
  resolveStatus,
  signedPips,
  validateLevels,
  type SignalInput,
  type SignalUpdateInput,
} from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';

const SIGNAL_INCLUDE = {
  updates: { orderBy: { createdAt: 'asc' } },
  images: { select: { id: true, url: true, brandedUrl: true, thumbnailUrl: true } },
} satisfies Prisma.SignalInclude;

type SignalWithRelations = Prisma.SignalGetPayload<{ include: typeof SIGNAL_INCLUDE }>;

@Injectable()
export class SignalsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
  ) {}

  /**
   * Create a signal from the admin composer or the MT5 bridge.
   *
   * Both callers hand over the same shape, so the auto-feed added later is a
   * new caller rather than a second definition of what a signal is. Every
   * derived number (stop distance, planned R:R) is computed here from the raw
   * levels — none of it is accepted from the caller.
   */
  async create(
    input: SignalInput,
    ctx: { authorId?: string | null; sourceKeyId?: string | null },
  ): Promise<SignalWithRelations> {
    const problems = validateLevels(input);
    if (problems.length) {
      throw new BadRequestException({ message: 'Invalid signal levels', problems });
    }

    const metrics = computeSignalMetrics(input);

    const signal = await this.prisma.signal.create({
      data: {
        symbol: input.symbol.toUpperCase(),
        direction: input.direction,
        orderType: input.orderType,
        entryLow: input.entryLow,
        entryHigh: input.entryHigh,
        sl: input.sl,
        tp1: input.tp1 ?? null,
        tp2: input.tp2 ?? null,
        tp3: input.tp3 ?? null,
        beTrigger: input.beTrigger ?? null,
        pipSize: input.pipSize ?? null,
        timeframe: input.timeframe,
        riskPercent: input.riskPercent ?? null,
        analysisText: input.analysisText,
        minPlan: input.minPlan as PlanCode,
        slPips: metrics.slPips,
        plannedRR: metrics.maxRR,
        status: input.publishNow ? 'PUBLISHED' : 'DRAFT',
        publishedAt: input.publishNow ? new Date() : null,
        authorId: ctx.authorId ?? null,
        sourceKeyId: ctx.sourceKeyId ?? null,
      },
      include: SIGNAL_INCLUDE,
    });

    if (input.imageIds.length) {
      await this.prisma.mediaAsset.updateMany({
        where: { id: { in: input.imageIds } },
        data: { signalId: signal.id },
      });
    }

    return this.findByIdOrThrow(signal.id);
  }

  async publish(id: string): Promise<SignalWithRelations> {
    const signal = await this.findByIdOrThrow(id);
    if (signal.status !== 'DRAFT') {
      throw new BadRequestException(`Only a draft can be published (this one is ${signal.status})`);
    }
    await this.prisma.signal.update({
      where: { id },
      data: { status: 'PUBLISHED', publishedAt: new Date() },
    });
    return this.findByIdOrThrow(id);
  }

  /**
   * Append an update to the ledger and recompute the signal's status from it.
   *
   * The status is never written directly — it is always a fold over the full
   * update history, so the badge a subscriber sees and the timeline they read
   * cannot disagree.
   */
  async addUpdate(
    id: string,
    input: SignalUpdateInput,
    createdById: string | null,
  ): Promise<SignalWithRelations> {
    const signal = await this.findByIdOrThrow(id);

    if (!canApplyUpdate(signal.status, input.type)) {
      throw new BadRequestException(
        `Cannot apply ${input.type} to a signal that is ${signal.status}`,
      );
    }

    const resultPips = this.realisedPips(signal, input);

    await this.prisma.signalUpdate.create({
      data: {
        signalId: id,
        type: input.type,
        note: input.note,
        price: input.price ?? null,
        resultPips,
        createdById,
      },
    });

    return this.recomputeStatus(id);
  }

  /** Recompute status and closing figures from the ledger. */
  private async recomputeStatus(id: string): Promise<SignalWithRelations> {
    const signal = await this.findByIdOrThrow(id);
    const types = signal.updates.map((u) => u.type as SignalUpdateType);

    const status = resolveStatus({
      published: signal.publishedAt !== null,
      updates: types,
    }) as SignalStatus;

    const closed = ['CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS', 'CANCELLED'].includes(status);

    // The realised result is the pip figure carried by the update that closed
    // the trade; a break-even scratch settles at zero by definition.
    const closingUpdate = [...signal.updates]
      .reverse()
      .find((u) => u.resultPips !== null && u.resultPips !== undefined);

    await this.prisma.signal.update({
      where: { id },
      data: {
        status,
        closedAt: closed ? (signal.closedAt ?? new Date()) : null,
        resultPips:
          status === 'CLOSED_BE' ? 0 : closed ? (closingUpdate?.resultPips ?? null) : null,
      },
    });

    return this.findByIdOrThrow(id);
  }

  /** Pips realised by an exit update, signed so profit is positive. */
  private realisedPips(
    signal: SignalWithRelations,
    input: SignalUpdateInput,
  ): number | null {
    const exitTypes: SignalUpdateType[] = [
      'TP1_HIT',
      'TP2_HIT',
      'TP3_HIT',
      'SL_HIT',
      'PARTIAL_CLOSE',
      'CLOSE_WIN',
      'CLOSE_LOSS',
    ];
    if (!exitTypes.includes(input.type)) return null;

    const metrics = computeSignalMetrics(this.toLevels(signal));
    const exitPrice =
      input.price ??
      (input.type === 'TP1_HIT'
        ? signal.tp1
        : input.type === 'TP2_HIT'
          ? signal.tp2
          : input.type === 'TP3_HIT'
            ? signal.tp3
            : input.type === 'SL_HIT'
              ? signal.sl
              : null);

    if (exitPrice == null) return null;

    return signedPips(signal.direction, metrics.entryRef, exitPrice, metrics.pipSize);
  }

  private toLevels(s: SignalWithRelations) {
    return {
      symbol: s.symbol,
      direction: s.direction,
      entryLow: s.entryLow,
      entryHigh: s.entryHigh,
      sl: s.sl,
      tp1: s.tp1,
      tp2: s.tp2,
      tp3: s.tp3,
      beTrigger: s.beTrigger,
      pipSize: s.pipSize,
    };
  }

  async findByIdOrThrow(id: string): Promise<SignalWithRelations> {
    const signal = await this.prisma.signal.findUnique({ where: { id }, include: SIGNAL_INCLUDE });
    if (!signal) throw new NotFoundException('Signal not found');
    return signal;
  }

  /**
   * Feed for a subscriber.
   *
   * Signals above the viewer's tier are still returned, but stripped to a
   * teaser: the symbol, direction and timing stay visible because that preview
   * is what sells the upgrade, while the levels — the part they are paying for —
   * are removed server-side rather than hidden by the client.
   */
  async feedForUser(
    userId: string | null,
    query: { symbol?: string; openOnly?: boolean; cursor?: string; limit: number },
  ) {
    const ent = await this.entitlements.forOptionalUser(userId);

    const where: Prisma.SignalWhereInput = {
      status: { not: 'DRAFT' },
      publishedAt: { not: null },
      ...(query.symbol ? { symbol: query.symbol.toUpperCase() } : {}),
      ...(query.openOnly
        ? { status: { in: ['PUBLISHED', 'ACTIVE', 'BE_SET', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT'] } }
        : {}),
    };

    const rows = await this.prisma.signal.findMany({
      where,
      include: SIGNAL_INCLUDE,
      orderBy: { publishedAt: 'desc' },
      take: query.limit + 1,
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    });

    const hasMore = rows.length > query.limit;
    const page = hasMore ? rows.slice(0, query.limit) : rows;

    return {
      items: page.map((s) => this.present(s, canAccessContent(ent.plan, s.minPlan))),
      nextCursor: hasMore ? page[page.length - 1].id : null,
      viewerPlan: ent.plan,
    };
  }

  async findForUser(id: string, userId: string | null) {
    const signal = await this.findByIdOrThrow(id);
    if (signal.status === 'DRAFT') throw new NotFoundException('Signal not found');

    const ent = await this.entitlements.forOptionalUser(userId);
    return this.present(signal, canAccessContent(ent.plan, signal.minPlan));
  }

  /**
   * Shape a signal for the wire.
   *
   * When `unlocked` is false the numeric levels are never serialised at all.
   * Sending them with a "locked" flag for the client to respect would put the
   * paid content in every free user's network log.
   */
  present(s: SignalWithRelations, unlocked: boolean) {
    const base = {
      id: s.id,
      symbol: s.symbol,
      direction: s.direction,
      orderType: s.orderType,
      timeframe: s.timeframe,
      status: s.status,
      minPlan: s.minPlan,
      publishedAt: s.publishedAt,
      closedAt: s.closedAt,
      createdAt: s.createdAt,
      unlocked,
    };

    if (!unlocked) {
      return {
        ...base,
        locked: true,
        // Enough to prove the signal exists and was timely, nothing more.
        updateCount: s.updates.length,
      };
    }

    const metrics = computeSignalMetrics(this.toLevels(s));

    return {
      ...base,
      locked: false,
      entryLow: s.entryLow,
      entryHigh: s.entryHigh,
      sl: s.sl,
      tp1: s.tp1,
      tp2: s.tp2,
      tp3: s.tp3,
      beTrigger: s.beTrigger,
      riskPercent: s.riskPercent,
      analysisText: s.analysisText,
      resultPips: s.resultPips,
      metrics,
      images: s.images.map((i) => ({
        id: i.id,
        url: i.brandedUrl ?? i.url,
        thumbnailUrl: i.thumbnailUrl,
      })),
      updates: s.updates.map((u) => ({
        id: u.id,
        type: u.type,
        note: u.note,
        price: u.price,
        resultPips: u.resultPips,
        imageUrl: u.imageUrl,
        createdAt: u.createdAt,
      })),
    };
  }

  /**
   * Public performance record, computed from the ledger rather than stored.
   *
   * Shown to free users as the reason to subscribe, which is exactly why it has
   * to be derived: the number on the marketing screen is the same number a
   * subscriber could total by hand from the feed.
   */
  async publicStats(days = 90) {
    const since = new Date(Date.now() - days * 86_400_000);
    const signals = await this.prisma.signal.findMany({
      where: { publishedAt: { gte: since, not: null }, status: { not: 'DRAFT' } },
      select: { status: true, resultPips: true, plannedRR: true, closedAt: true },
    });

    return { windowDays: days, ...computeStats(signals) };
  }

  async listForAdmin(query: { limit: number; cursor?: string; status?: string }) {
    const rows = await this.prisma.signal.findMany({
      where: query.status ? { status: query.status as SignalStatus } : {},
      include: SIGNAL_INCLUDE,
      orderBy: { createdAt: 'desc' },
      take: query.limit + 1,
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    });

    const hasMore = rows.length > query.limit;
    const page = hasMore ? rows.slice(0, query.limit) : rows;

    // Admins always see full detail — that is the point of the console.
    return {
      items: page.map((s) => this.present(s, true)),
      nextCursor: hasMore ? page[page.length - 1].id : null,
    };
  }

  async remove(id: string): Promise<void> {
    await this.prisma.signal.delete({ where: { id } });
  }
}
