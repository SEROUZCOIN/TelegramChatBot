import {
  BadRequestException,
  Controller,
  InternalServerErrorException,
  Logger,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import type { FastifyRequest } from 'fastify';
import { CurrentUser, Roles } from '../common/decorators';
import { MediaService } from './media.service';

@Controller('admin/media')
@Roles('ADMIN')
export class MediaController {
  private readonly logger = new Logger(MediaController.name);

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
    const multipart = req as FastifyRequest & {
      file?: () => Promise<MultipartFile | undefined>;
    };

    if (typeof multipart.file !== 'function') {
      // Registration order matters: without @fastify/multipart on the instance
      // this decorator is absent, and the failure otherwise surfaces as an
      // opaque 500 with nothing in the log.
      throw new BadRequestException('Multipart handling is not available on this server');
    }

    let file: MultipartFile | undefined;
    try {
      file = await multipart.file();
    } catch (err) {
      this.logger.error('Reading the multipart body failed', err as Error);
      throw new BadRequestException('Could not read the uploaded file');
    }

    if (!file) throw new BadRequestException('No file uploaded');

    try {
      const buffer = await file.toBuffer();

      return await this.media.uploadImage({
        buffer,
        mimetype: file.mimetype,
        uploadedById: userId,
        brand:
          symbol && direction
            ? { symbol: symbol.toUpperCase(), direction: direction.toUpperCase() }
            : null,
      });
    } catch (err) {
      if (err instanceof BadRequestException) throw err;
      // An image pipeline has many ways to fail — an unreadable file, a codec
      // sharp was not built with, a storage backend that is not reachable. A
      // bare 500 makes all of them look identical.
      this.logger.error('Chart upload failed', err as Error);
      throw new InternalServerErrorException(
        `Upload failed: ${err instanceof Error ? err.message : 'unknown error'}`,
      );
    }
  }
}

interface MultipartFile {
  mimetype: string;
  toBuffer(): Promise<Buffer>;
}
