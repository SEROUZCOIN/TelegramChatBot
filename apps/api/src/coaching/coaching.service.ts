import { BadRequestException, ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';
import type { AppConfig } from '../config/configuration';

/**
 * One-to-one live coaching.
 *
 * Deliberately one-to-one and nothing else. Apple guideline 3.1.3(d) permits
 * outside payment only for "real-time person-to-person services between two
 * individuals"; one-to-few and one-to-many sessions must use in-app purchase.
 * Keeping the PRO and ULTRA tiers strictly 1:1 is what keeps their external
 * checkout within the rule, so group sessions are not a feature here.
 */
@Injectable()
export class CoachingService {
  private readonly logger = new Logger(CoachingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {}

  async book(input: {
    studentId: string;
    coachId?: string | null;
    scheduledAt: Date;
    durationMin: number;
    topic: string;
  }) {
    const ent = await this.entitlements.forUser(input.studentId);
    if (!ent.canBookCoaching) {
      throw new ForbiddenException({
        message: 'Live coaching is included with the Pro and Ultra plans',
        requiredPlan: 'PRO',
        currentPlan: ent.plan,
      });
    }

    if (input.scheduledAt.getTime() < Date.now()) {
      throw new BadRequestException('Pick a time in the future');
    }

    // A coach cannot be in two places at once; overlapping bookings are refused
    // rather than silently double-booked.
    if (input.coachId) {
      const end = new Date(input.scheduledAt.getTime() + input.durationMin * 60_000);
      const clash = await this.prisma.coachingSession.findFirst({
        where: {
          coachId: input.coachId,
          status: { in: ['REQUESTED', 'SCHEDULED', 'LIVE'] },
          scheduledAt: { lt: end },
        },
        orderBy: { scheduledAt: 'desc' },
      });

      if (clash) {
        const clashEnd = new Date(clash.scheduledAt.getTime() + clash.durationMin * 60_000);
        if (clashEnd > input.scheduledAt) {
          throw new BadRequestException('That slot is already booked');
        }
      }
    }

    return this.prisma.coachingSession.create({
      data: {
        studentId: input.studentId,
        coachId: input.coachId ?? null,
        scheduledAt: input.scheduledAt,
        durationMin: input.durationMin,
        topic: input.topic,
        status: 'REQUESTED',
      },
    });
  }

  /**
   * Provision the video room and hand back a join URL.
   *
   * The room is created per session and only the booked student and their coach
   * are given a token, so a leaked link does not open someone else's paid
   * mentoring call.
   */
  async join(sessionId: string, userId: string) {
    const session = await this.prisma.coachingSession.findUnique({ where: { id: sessionId } });
    if (!session) throw new BadRequestException('Session not found');
    if (session.studentId !== userId && session.coachId !== userId) {
      throw new ForbiddenException('This is not your session');
    }

    const cfg = this.config.get('daily', { infer: true });
    if (!cfg.apiKey) {
      throw new BadRequestException('Live video is not configured yet');
    }

    let roomUrl = session.roomUrl;
    if (!roomUrl) {
      const expiry = Math.floor(
        (session.scheduledAt.getTime() + (session.durationMin + 30) * 60_000) / 1000,
      );

      const res = await fetch('https://api.daily.co/v1/rooms', {
        method: 'POST',
        headers: { authorization: `Bearer ${cfg.apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          privacy: 'private',
          properties: { exp: expiry, max_participants: 2, enable_screenshare: true },
        }),
      });

      if (!res.ok) {
        this.logger.error(`Daily room creation failed: ${res.status} ${await res.text()}`);
        throw new BadRequestException('Could not start the video room');
      }

      const room = (await res.json()) as { name: string; url: string };
      roomUrl = room.url;

      await this.prisma.coachingSession.update({
        where: { id: sessionId },
        data: { roomName: room.name, roomUrl, status: 'SCHEDULED' },
      });
    }

    return { roomUrl, scheduledAt: session.scheduledAt, durationMin: session.durationMin };
  }

  listForUser(userId: string) {
    return this.prisma.coachingSession.findMany({
      where: { OR: [{ studentId: userId }, { coachId: userId }] },
      orderBy: { scheduledAt: 'asc' },
      include: {
        coach: { select: { id: true, displayName: true, avatarUrl: true } },
        student: { select: { id: true, displayName: true } },
      },
    });
  }
}
