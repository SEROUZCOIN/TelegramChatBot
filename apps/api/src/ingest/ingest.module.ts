import { Module } from '@nestjs/common';
import { IngestController } from './ingest.controller';
import { SignalsModule } from '../signals/signals.module';

@Module({ imports: [SignalsModule], controllers: [IngestController] })
export class IngestModule {}
