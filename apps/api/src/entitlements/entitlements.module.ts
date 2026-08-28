import { Global, Module } from '@nestjs/common';
import { EntitlementsController } from './entitlements.controller';
import { EntitlementsService } from './entitlements.service';

@Global()
@Module({
  controllers: [EntitlementsController],
  providers: [EntitlementsService],
  exports: [EntitlementsService],
})
export class EntitlementsModule {}
