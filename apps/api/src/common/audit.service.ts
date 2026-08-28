import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from './prisma.service';

/**
 * Append-only record of every administrative action.
 *
 * Needed for more than tidiness: this platform edits prices, grants paid
 * entitlements by hand, and approves bank transfers, so "who granted this Ultra
 * subscription and when" has to be answerable after the fact.
 */
@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(entry: {
    actorId?: string | null;
    action: string;
    entity: string;
    entityId?: string | null;
    before?: unknown;
    after?: unknown;
    ip?: string | null;
  }): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: entry.actorId ?? null,
          action: entry.action,
          entity: entry.entity,
          entityId: entry.entityId ?? null,
          before: (entry.before ?? undefined) as never,
          after: (entry.after ?? undefined) as never,
          ip: entry.ip ?? null,
        },
      });
    } catch (err) {
      // An audit write must never take down the action it is recording.
      this.logger.error(`Failed to write audit log for ${entry.action}`, err as Error);
    }
  }
}
