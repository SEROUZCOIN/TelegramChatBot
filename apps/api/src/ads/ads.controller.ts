import { Body, Controller, Get, Put } from '@nestjs/common';
import { adPlacementSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';

@Controller('ads')
export class AdsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
  ) {}

  /**
   * Ad configuration for this specific viewer.
   *
   * Suppression is resolved here rather than sent as a flag for the app to
   * honour: a subscriber who paid $1,500 or $5,000 must never see an ad, and
   * "the client was supposed to hide it" is not a guarantee. A suppressed slot
   * is simply absent from the response, so a stale build has no unit id to
   * render even if it wanted to.
   */
  @Get('config')
  async config(@CurrentUser('id') userId: string) {
    const ent = await this.entitlements.forUser(userId);
    const placements = await this.prisma.adPlacement.findMany({ where: { isEnabled: true } });

    const visible = placements.filter((p) => !p.hideForPlans.includes(ent.plan));

    return {
      showAds: ent.showAds,
      plan: ent.plan,
      placements: ent.showAds
        ? visible.map((p) => ({
            slot: p.slot,
            network: p.network,
            unitIdIos: p.unitIdIos,
            unitIdAndroid: p.unitIdAndroid,
            minIntervalSec: p.minIntervalSec,
          }))
        : [],
    };
  }
}

@Controller('admin/ads')
@Roles('ADMIN')
export class AdminAdsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  list() {
    return this.prisma.adPlacement.findMany({ orderBy: { slot: 'asc' } });
  }

  @Put()
  upsert(
    @Body(new ZodValidationPipe(adPlacementSchema)) body: z.infer<typeof adPlacementSchema>,
  ) {
    return this.prisma.adPlacement.upsert({
      where: { slot: body.slot },
      create: body,
      update: body,
    });
  }
}
