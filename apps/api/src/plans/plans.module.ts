import { Module } from '@nestjs/common';
import { AdminPlansController, PlansController } from './plans.controller';
import { PaymentsModule } from '../payments/payments.module';

@Module({ imports: [PaymentsModule], controllers: [PlansController, AdminPlansController] })
export class PlansModule {}
