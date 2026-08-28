import { Controller, Get } from '@nestjs/common';
import { CurrentUser } from '../common/decorators';
import { EntitlementsService } from './entitlements.service';

@Controller('me')
export class EntitlementsController {
  constructor(private readonly entitlements: EntitlementsService) {}

  /**
   * The client's source of truth for what it may render. It is deliberately
   * cheap and called on every foreground so a lapsed subscription locks up
   * promptly rather than at the next cold start.
   */
  @Get('entitlements')
  get(@CurrentUser('id') userId: string) {
    return this.entitlements.forUser(userId);
  }
}
