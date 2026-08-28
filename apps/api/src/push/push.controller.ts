import { Body, Controller, Get, Post } from '@nestjs/common';
import { deviceRegisterSchema, pushCampaignSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { PushService } from './push.service';

@Controller('devices')
export class DevicesController {
  constructor(private readonly push: PushService) {}

  @Post()
  register(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(deviceRegisterSchema)) body: z.infer<typeof deviceRegisterSchema>,
  ) {
    return this.push.registerDevice(userId, body.pushToken, body.platform, body.appVersion);
  }
}

@Controller('admin/push')
@Roles('ADMIN')
export class AdminPushController {
  constructor(
    private readonly push: PushService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('campaigns')
  list() {
    return this.prisma.pushCampaign.findMany({ orderBy: { createdAt: 'desc' }, take: 50 });
  }

  @Post('campaigns')
  async create(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(pushCampaignSchema)) body: z.infer<typeof pushCampaignSchema>,
  ) {
    const campaign = await this.prisma.pushCampaign.create({
      data: { ...body, scheduledAt: body.scheduledAt ?? null, createdById: userId },
    });

    // Send immediately when no schedule was set; the cron picks up the rest.
    if (!campaign.scheduledAt) await this.push.sendCampaign(campaign.id);
    return campaign;
  }
}
