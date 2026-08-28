import { BadRequestException, Controller, Post, Query, Req } from '@nestjs/common';
import type { FastifyRequest } from 'fastify';
import { CurrentUser, Roles } from '../common/decorators';
import { MediaService } from './media.service';

@Controller('admin/media')
@Roles('ADMIN')
export class MediaController {
  constructor(private readonly media: MediaService) {}

  /**
   * Chart screenshot upload for the signal composer.
   *
   * Passing ?symbol and ?direction produces the watermarked variant that gets
   * published to the app and Telegram.
   */
  @Post('upload')
  async upload(
    @Req() req: FastifyRequest,
    @CurrentUser('id') userId: string,
    @Query('symbol') symbol?: string,
    @Query('direction') direction?: string,
  ) {
    const file = await (req as FastifyRequest & { file?: () => Promise<MultipartFile | undefined> })
      .file?.();
    if (!file) throw new BadRequestException('No file uploaded');

    const buffer = await file.toBuffer();

    return this.media.uploadImage({
      buffer,
      mimetype: file.mimetype,
      uploadedById: userId,
      brand: symbol && direction ? { symbol: symbol.toUpperCase(), direction: direction.toUpperCase() } : null,
    });
  }
}

interface MultipartFile {
  mimetype: string;
  toBuffer(): Promise<Buffer>;
}
