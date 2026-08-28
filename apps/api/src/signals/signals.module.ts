import { Module } from '@nestjs/common';
import { AdminSignalsController, SignalsController } from './signals.controller';
import { SignalsService } from './signals.service';
import { SignalBroadcastService } from './signal-broadcast.service';
import { PushModule } from '../push/push.module';
import { TelegramModule } from '../telegram/telegram.module';

@Module({
  imports: [PushModule, TelegramModule],
  controllers: [SignalsController, AdminSignalsController],
  providers: [SignalsService, SignalBroadcastService],
  exports: [SignalsService, SignalBroadcastService],
})
export class SignalsModule {}
