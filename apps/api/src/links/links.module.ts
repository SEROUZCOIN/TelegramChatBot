import { Module } from '@nestjs/common';
import { AdminLinksController, LinksController } from './links.controller';

@Module({ controllers: [LinksController, AdminLinksController] })
export class LinksModule {}
