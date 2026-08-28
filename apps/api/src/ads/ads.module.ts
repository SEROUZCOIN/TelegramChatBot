import { Module } from '@nestjs/common';
import { AdminAdsController, AdsController } from './ads.controller';

@Module({ controllers: [AdsController, AdminAdsController] })
export class AdsModule {}
