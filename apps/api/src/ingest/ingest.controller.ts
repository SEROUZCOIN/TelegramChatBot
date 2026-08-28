import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { signalInputSchema, signalUpdateInputSchema, type SignalInput } from '@tsp/shared';
import { z } from 'zod';
import { Public } from '../common/decorators';
import { IngestKeyGuard } from '../common/guards/ingest-key.guard';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { SignalsService } from '../signals/signals.service';
import { SignalBroadcastService } from '../signals/signal-broadcast.service';

/** The EA reports by instrument, so the update carries the symbol it belongs to. */
const ingestUpdateSchema = signalUpdateInputSchema.extend({
  symbol: z.string().min(2).max(24),
});

/**
 * Machine ingest for the MetaTrader 5 bridge.
 *
 * This endpoint accepts the *same* `signalInputSchema` the admin composer
 * posts. That was the point of defining the contract in `@tsp/shared` up front:
 * turning on the MT5 auto-feed adds a caller, it does not require a second
 * definition of what a signal is or a rewrite of the composer path.
 *
 * Authenticated by `X-Ingest-Key` rather than a user session, so a compromised
 * trading VPS is revoked on its own without touching anyone's login.
 */
@Controller('ingest')
@Public()
@UseGuards(IngestKeyGuard)
export class IngestController {
  constructor(
    private readonly signals: SignalsService,
    private readonly broadcast: SignalBroadcastService,
    private readonly prisma: PrismaService,
  ) {}

  @Post('signals')
  async createSignal(
    @Body(new ZodValidationPipe(signalInputSchema)) body: SignalInput,
    @Req() req: { ingestKeyId?: string },
  ) {
    const signal = await this.signals.create(body, { sourceKeyId: req.ingestKeyId ?? null });
    if (signal.status === 'PUBLISHED') await this.broadcast.onPublished(signal.id);
    return { id: signal.id, status: signal.status };
  }

  /**
   * Position updates from the EA — the stop moved to break-even, a target
   * filled, the position closed. Keyed by the EA's own ticket so a retry after
   * a dropped connection does not append the same update twice.
   */
  @Post('signals/updates')
  async addUpdate(
    @Body(new ZodValidationPipe(ingestUpdateSchema)) body: z.infer<typeof ingestUpdateSchema>,
  ) {
    const signal = await this.prisma.signal.findFirst({
      where: { symbol: body.symbol.toUpperCase(), status: { notIn: ['CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS', 'CANCELLED'] } },
      orderBy: { createdAt: 'desc' },
    });
    if (!signal) return { matched: false };

    const duplicate = await this.prisma.signalUpdate.findFirst({
      where: { signalId: signal.id, type: body.type },
    });
    if (duplicate) return { matched: true, duplicate: true };

    await this.signals.addUpdate(signal.id, { type: body.type, note: body.note, price: body.price, imageId: null }, null);
    await this.broadcast.onUpdated(signal.id, body.type);
    return { matched: true, duplicate: false };
  }
}
