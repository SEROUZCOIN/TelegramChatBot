import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';

import configuration from './config/configuration';
import { CommonModule } from './common/common.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';

import { AdminModule } from './admin/admin.module';
import { AdsModule } from './ads/ads.module';
import { AuthModule } from './auth/auth.module';
import { CoachingModule } from './coaching/coaching.module';
import { CoursesModule } from './courses/courses.module';
import { EntitlementsModule } from './entitlements/entitlements.module';
import { IngestModule } from './ingest/ingest.module';
import { LinksModule } from './links/links.module';
import { MediaModule } from './media/media.module';
import { PaymentsModule } from './payments/payments.module';
import { PlansModule } from './plans/plans.module';
import { PushModule } from './push/push.module';
import { SignalsModule } from './signals/signals.module';
import { TelegramModule } from './telegram/telegram.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [configuration] }),
    ScheduleModule.forRoot(),
    CommonModule,
    EntitlementsModule,
    AuthModule,
    UsersModule,
    PlansModule,
    PaymentsModule,
    SignalsModule,
    MediaModule,
    CoursesModule,
    CoachingModule,
    AdsModule,
    LinksModule,
    PushModule,
    TelegramModule,
    IngestModule,
    AdminModule,
  ],
  providers: [
    // Authentication is on by default and opted out of with @Public, so a new
    // controller cannot accidentally ship unauthenticated.
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule {}
