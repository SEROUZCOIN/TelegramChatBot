import { Body, Controller, Get, Param, Post, Put } from '@nestjs/common';
import { courseInputSchema, lessonInputSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { CoursesService } from './courses.service';

const progressSchema = z.object({
  watchedSec: z.number().int().min(0),
  completed: z.boolean().default(false),
});

@Controller('courses')
export class CoursesController {
  constructor(private readonly courses: CoursesService) {}

  @Get()
  catalogue(@CurrentUser('id') userId: string) {
    return this.courses.catalogue(userId);
  }

  @Get('progress')
  progress(@CurrentUser('id') userId: string) {
    return this.courses.progressFor(userId);
  }

  /** The only route that yields a playable video, and only after an entitlement check. */
  @Get('lessons/:id/playback')
  playback(@Param('id') lessonId: string, @CurrentUser('id') userId: string) {
    return this.courses.playback(lessonId, userId);
  }

  @Post('lessons/:id/progress')
  recordProgress(
    @Param('id') lessonId: string,
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(progressSchema)) body: z.infer<typeof progressSchema>,
  ) {
    return this.courses.recordProgress(userId, lessonId, body.watchedSec, body.completed);
  }
}

@Controller('admin/courses')
@Roles('ADMIN')
export class AdminCoursesController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  list() {
    return this.prisma.course.findMany({
      orderBy: { sortOrder: 'asc' },
      include: { lessons: { orderBy: { order: 'asc' } } },
    });
  }

  @Post()
  async create(
    @Body(new ZodValidationPipe(courseInputSchema)) body: z.infer<typeof courseInputSchema>,
  ) {
    const coverUrl = body.coverImageId
      ? (await this.prisma.mediaAsset.findUnique({ where: { id: body.coverImageId } }))?.url
      : null;

    const { coverImageId: _ignored, ...rest } = body;
    return this.prisma.course.create({ data: { ...rest, coverUrl } });
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(courseInputSchema.partial()))
    body: Partial<z.infer<typeof courseInputSchema>>,
  ) {
    const { coverImageId: _ignored, ...rest } = body;
    return this.prisma.course.update({ where: { id }, data: rest });
  }

  @Post('lessons')
  createLesson(
    @Body(new ZodValidationPipe(lessonInputSchema)) body: z.infer<typeof lessonInputSchema>,
  ) {
    return this.prisma.lesson.create({ data: body });
  }

  @Put('lessons/:id')
  updateLesson(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(lessonInputSchema.partial()))
    body: Partial<z.infer<typeof lessonInputSchema>>,
  ) {
    return this.prisma.lesson.update({ where: { id }, data: body });
  }
}
