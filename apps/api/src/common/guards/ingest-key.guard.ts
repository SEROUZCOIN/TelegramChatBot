import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../prisma.service';

/**
 * Authenticates the MT5 Expert Advisor bridge via `X-Ingest-Key`.
 *
 * Kept separate from user auth so a compromised trading VPS can be revoked on
 * its own without touching anyone's session. Keys are stored hashed and
 * compared in constant time.
 */
@Injectable()
export class IngestKeyGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<{
      headers: Record<string, string | undefined>;
      ingestKeyId?: string;
    }>();

    const presented = req.headers['x-ingest-key'];
    if (!presented) throw new UnauthorizedException('Missing X-Ingest-Key');

    const hash = createHash('sha256').update(presented).digest();
    const candidates = await this.prisma.ingestKey.findMany({ where: { isActive: true } });

    const match = candidates.find((k) => {
      const stored = Buffer.from(k.keyHash, 'hex');
      return stored.length === hash.length && timingSafeEqual(stored, hash);
    });

    if (!match) throw new UnauthorizedException('Invalid ingest key');

    await this.prisma.ingestKey.update({
      where: { id: match.id },
      data: { lastUsedAt: new Date() },
    });
    req.ingestKeyId = match.id;
    return true;
  }
}
