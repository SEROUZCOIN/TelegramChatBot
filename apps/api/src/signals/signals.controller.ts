import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import {
  signalInputSchema,
  signalQuerySchema,
  signalUpdateInputSchema,
  type SignalInput,
  type SignalUpdateInput,
} from '@tsp/shared';
import { CurrentUser, Public, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { AuditService } from '../common/audit.service';
import { SignalsService } from './signals.service';
import { SignalBroadcastService } from './signal-broadcast.service';

@Controller('signals')
export class SignalsController {
  constructor(
    private readonly signals: SignalsService,
    private readonly broadcast: SignalBroadcastService,
  ) {}

  @Get()
  feed(
    @CurrentUser('id') userId: string,
    @Query(new ZodValidationPipe(signalQuerySchema)) query: ReturnType<typeof signalQuerySchema.parse>,
  ) {
    return this.signals.feedForUser(userId, query);
  }

  /**
   * Public performance record. Deliberately unauthenticated: it is the proof a
   * prospective subscriber looks at before paying, and gating it would defeat
   * the purpose.
   */
  @Public()
  @Get('stats')
  stats(@Query('days') days?: string) {
    return this.signals.publicStats(days ? Number(days) : 90);
  }

  @Get(':id')
  findOne(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.signals.findForUser(id, userId);
  }
}

@Controller('admin/signals')
@Roles('ADMIN')
export class AdminSignalsController {
  constructor(
    private readonly signals: SignalsService,
    private readonly broadcast: SignalBroadcastService,
    private readonly audit: AuditService,
  ) {}

  @Get()
  list(@Query('limit') limit = '25', @Query('cursor') cursor?: string, @Query('status') status?: string) {
    return this.signals.listForAdmin({ limit: Number(limit), cursor, status });
  }

  @Post()
  async create(
    @Body(new ZodValidationPipe(signalInputSchema)) body: SignalInput,
    @CurrentUser('id') userId: string,
  ) {
    const signal = await this.signals.create(body, { authorId: userId });
    await this.audit.record({
      actorId: userId,
      action: 'signal.create',
      entity: 'Signal',
      entityId: signal.id,
      after: { symbol: signal.symbol, direction: signal.direction, status: signal.status },
    });

    if (signal.status === 'PUBLISHED') await this.broadcast.onPublished(signal.id);
    return this.signals.present(signal, true);
  }

  @Post(':id/publish')
  async publish(@Param('id') id: string, @CurrentUser('id') userId: string) {
    const signal = await this.signals.publish(id);
    await this.audit.record({
      actorId: userId,
      action: 'signal.publish',
      entity: 'Signal',
      entityId: id,
    });
    await this.broadcast.onPublished(id);
    return this.signals.present(signal, true);
  }

  /**
   * The one-tap update console: Entry Hit, Move to BE, TP1/2/3, SL, Close.
   *
   * Each tap appends to the ledger, recomputes the status, pushes to
   * subscribers, and edits the existing Telegram message rather than posting a
   * new one — so a channel reads as one live thread per trade.
   */
  @Post(':id/updates')
  async addUpdate(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(signalUpdateInputSchema)) body: SignalUpdateInput,
    @CurrentUser('id') userId: string,
  ) {
    const signal = await this.signals.addUpdate(id, body, userId);
    await this.audit.record({
      actorId: userId,
      action: `signal.update.${body.type}`,
      entity: 'Signal',
      entityId: id,
      after: { status: signal.status, price: body.price },
    });
    await this.broadcast.onUpdated(id, body.type);
    return this.signals.present(signal, true);
  }

  @Delete(':id')
  async remove(@Param('id') id: string, @CurrentUser('id') userId: string) {
    await this.signals.remove(id);
    await this.audit.record({
      actorId: userId,
      action: 'signal.delete',
      entity: 'Signal',
      entityId: id,
    });
    return { deleted: true };
  }
}
