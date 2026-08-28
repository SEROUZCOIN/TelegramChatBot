import { Module } from '@nestjs/common';
import { AdminCoachingController, CoachingController } from './coaching.controller';
import { CoachingService } from './coaching.service';

@Module({
  controllers: [CoachingController, AdminCoachingController],
  providers: [CoachingService],
})
export class CoachingModule {}
