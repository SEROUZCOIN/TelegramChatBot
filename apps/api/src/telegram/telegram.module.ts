import { Module } from '@nestjs/common';
import { TelegramBotService } from './telegram.bot';
import { TelegramController } from './telegram.controller';
import { TelegramPublisher } from './telegram.publisher';

@Module({
  controllers: [TelegramController],
  providers: [TelegramPublisher, TelegramBotService],
  exports: [TelegramPublisher, TelegramBotService],
})
export class TelegramModule {}
