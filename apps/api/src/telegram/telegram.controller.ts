import { Body, Controller, Post } from '@nestjs/common';
import { telegramBroadcastSchema } from '@tsp/shared';
import { z } from 'zod';
import { AuditService } from '../common/audit.service';
import { CurrentUser, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';
import { TelegramPublisher } from './telegram.publisher';

@Controller('admin/telegram')
@Roles('ADMIN')
export class TelegramController {
  constructor(
    private readonly publisher: TelegramPublisher,
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  @Post('broadcast')
  async broadcast(
    @CurrentUser('id') actorId: string,
    @Body(new ZodValidationPipe(telegramBroadcastSchema))
    body: z.infer<typeof telegramBroadcastSchema>,
  ) {
    const imageUrl = body.imageId
      ? (await this.prisma.mediaAsset.findUnique({ where: { id: body.imageId } }))?.url
      : null;

    const result = await this.publisher.broadcast(body.text, body.audiencePlans, imageUrl);

    await this.audit.record({
      actorId,
      action: 'telegram.broadcast',
      entity: 'Telegram',
      after: { audiencePlans: body.audiencePlans, sent: result.sent },
    });

    return result;
  }
}
