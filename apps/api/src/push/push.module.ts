import { Module } from '@nestjs/common';
import { AdminPushController, DevicesController } from './push.controller';
import { PushService } from './push.service';

@Module({
  controllers: [DevicesController, AdminPushController],
  providers: [PushService],
  exports: [PushService],
})
export class PushModule {}
