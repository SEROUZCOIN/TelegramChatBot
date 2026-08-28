import { Body, Controller, Get, Param, Post, Put } from '@nestjs/common';
import { coachingBookingSchema, coachingStatusSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { CoachingService } from './coaching.service';

@Controller('coaching')
export class CoachingController {
  constructor(private readonly coaching: CoachingService) {}

  @Get('sessions')
  list(@CurrentUser('id') userId: string) {
    return this.coaching.listForUser(userId);
  }

  @Post('sessions')
  book(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(coachingBookingSchema)) body: z.infer<typeof coachingBookingSchema>,
  ) {
    return this.coaching.book({
      studentId: userId,
      coachId: body.coachId,
      scheduledAt: body.scheduledAt,
      durationMin: body.durationMin,
      topic: body.topic,
    });
  }

  @Post('sessions/:id/join')
  join(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.coaching.join(id, userId);
  }
}

@Controller('admin/coaching')
@Roles('ADMIN', 'COACH')
export class AdminCoachingController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('sessions')
  list() {
    return this.prisma.coachingSession.findMany({
      orderBy: { scheduledAt: 'asc' },
      include: {
        student: { select: { id: true, displayName: true, email: true } },
        coach: { select: { id: true, displayName: true } },
      },
    });
  }

  @Put('sessions/:id')
  update(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(coachingStatusSchema)) body: z.infer<typeof coachingStatusSchema>,
  ) {
    return this.prisma.coachingSession.update({ where: { id }, data: body });
  }
}
