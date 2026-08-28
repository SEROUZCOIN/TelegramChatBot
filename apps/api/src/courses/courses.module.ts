import { Module } from '@nestjs/common';
import { AdminCoursesController, CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';
import { VideoService } from './video.service';

@Module({
  controllers: [CoursesController, AdminCoursesController],
  providers: [CoursesService, VideoService],
  exports: [CoursesService, VideoService],
})
export class CoursesModule {}
