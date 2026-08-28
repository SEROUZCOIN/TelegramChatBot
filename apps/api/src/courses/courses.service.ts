import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { PlanCode } from '@prisma/client';
import { canAccessContent } from '@tsp/shared';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { VideoService } from './video.service';

@Injectable()
export class CoursesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly video: VideoService,
  ) {}

  /**
   * Course catalogue.
   *
   * Locked courses stay visible — the catalogue is the sales pitch for the
   * video plan — but a locked lesson is returned without its video UID.
   */
  async catalogue(userId: string | null) {
    const ent = await this.entitlements.forOptionalUser(userId);

    const courses = await this.prisma.course.findMany({
      where: { isPublished: true },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
      include: {
        lessons: {
          orderBy: { order: 'asc' },
          select: {
            id: true,
            title: true,
            description: true,
            durationSec: true,
            order: true,
            isFreePreview: true,
          },
        },
      },
    });

    return {
      viewerPlan: ent.plan,
      items: courses.map((c) => {
        const unlocked = canAccessContent(ent.plan, c.minPlan);
        return {
          id: c.id,
          title: c.title,
          slug: c.slug,
          description: c.description,
          level: c.level,
          coverUrl: c.coverUrl,
          minPlan: c.minPlan,
          unlocked,
          lessonCount: c.lessons.length,
          totalDurationSec: c.lessons.reduce((sum, l) => sum + l.durationSec, 0),
          lessons: c.lessons.map((l) => ({
            ...l,
            // A free preview stays playable on any tier: it is the funnel.
            playable: unlocked || l.isFreePreview,
          })),
        };
      }),
    };
  }

  /**
   * Exchange a lesson id for a signed playback URL.
   *
   * This is the only path to video. The entitlement is checked here, on the
   * server, immediately before the token is minted.
   */
  async playback(lessonId: string, userId: string) {
    const lesson = await this.prisma.lesson.findUnique({
      where: { id: lessonId },
      include: { course: { select: { minPlan: true, isPublished: true } } },
    });

    if (!lesson || !lesson.course.isPublished) throw new NotFoundException('Lesson not found');

    // Entitlement is checked before anything is reported about the lesson's
    // contents: answering "no video yet" first would tell a user who cannot
    // open the lesson which parts of the paid library are still empty.
    const ent = await this.entitlements.forUser(userId);
    const allowed =
      lesson.isFreePreview || canAccessContent(ent.plan, lesson.course.minPlan as PlanCode);

    if (!allowed) {
      throw new ForbiddenException({
        message: 'Your plan does not include this lesson',
        requiredPlan: lesson.course.minPlan,
        currentPlan: ent.plan,
      });
    }

    if (!lesson.videoUid) throw new NotFoundException('This lesson has no video yet');

    const { token, expiresAt } = this.video.signPlaybackToken(lesson.videoUid, userId);

    // Note what is absent: `videoUid` is never in this response.
    return { lessonId: lesson.id, ...this.video.playbackUrls(token), expiresAt };
  }

  async recordProgress(userId: string, lessonId: string, watchedSec: number, completed: boolean) {
    return this.prisma.lessonProgress.upsert({
      where: { userId_lessonId: { userId, lessonId } },
      create: {
        userId,
        lessonId,
        watchedSec,
        completedAt: completed ? new Date() : null,
      },
      update: {
        watchedSec,
        ...(completed ? { completedAt: new Date() } : {}),
      },
    });
  }

  async progressFor(userId: string) {
    return this.prisma.lessonProgress.findMany({ where: { userId } });
  }
}
