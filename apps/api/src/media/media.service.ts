import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { PrismaService } from '../common/prisma.service';
import { StorageService } from './storage.service';

const MAX_BYTES = 12 * 1024 * 1024;
const ALLOWED = new Set(['image/jpeg', 'image/png', 'image/webp']);

@Injectable()
export class MediaService {
  private readonly logger = new Logger(MediaService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  /**
   * Store a chart screenshot and derive its public variants.
   *
   * Three files come out of one upload: the original (kept private), a
   * watermarked copy that is what actually gets published, and a thumbnail for
   * the feed. Watermarking on the server rather than in the composer means a
   * screenshot cannot reach a channel unbranded because someone skipped a step.
   */
  async uploadImage(input: {
    buffer: Buffer;
    mimetype: string;
    uploadedById: string;
    brand?: { symbol: string; direction: string } | null;
  }) {
    if (!ALLOWED.has(input.mimetype)) {
      throw new BadRequestException(`Unsupported image type ${input.mimetype}`);
    }
    if (input.buffer.byteLength > MAX_BYTES) {
      throw new BadRequestException('Image exceeds the 12 MB limit');
    }

    const id = randomUUID();
    const base = sharp(input.buffer, { failOn: 'error' }).rotate();
    const meta = await base.metadata();

    const normalised = await base.clone().webp({ quality: 88 }).toBuffer();
    const thumbnail = await base
      .clone()
      .resize({ width: 480, withoutEnlargement: true })
      .webp({ quality: 78 })
      .toBuffer();

    const [url, thumbnailUrl] = await Promise.all([
      this.storage.put(`signals/${id}.webp`, normalised, 'image/webp'),
      this.storage.put(`signals/${id}-thumb.webp`, thumbnail, 'image/webp'),
    ]);

    let brandedUrl: string | null = null;
    if (input.brand) {
      const branded = await this.brand(normalised, input.brand, meta.width ?? 1200);
      brandedUrl = await this.storage.put(`signals/${id}-branded.webp`, branded, 'image/webp');
    }

    return this.prisma.mediaAsset.create({
      data: {
        id,
        type: 'IMAGE',
        provider: 'S3',
        key: `signals/${id}.webp`,
        url,
        thumbnailUrl,
        brandedUrl,
        width: meta.width ?? null,
        height: meta.height ?? null,
        bytes: normalised.byteLength,
        uploadedById: input.uploadedById,
      },
    });
  }

  /** Overlay a symbol/direction caption bar onto a chart screenshot. */
  private async brand(
    image: Buffer,
    brand: { symbol: string; direction: string },
    width: number,
  ): Promise<Buffer> {
    // Bar height scales with the image but is clamped, so the caption stays
    // readable on a phone screenshot without swallowing a small one.
    const barHeight = Math.min(Math.max(28, Math.round(width * 0.06)), 96);
    const fontSize = Math.round(barHeight * 0.42);
    const padding = Math.round(barHeight * 0.35);
    const accent = brand.direction === 'BUY' ? '#16a34a' : '#dc2626';

    // The symbol is anchored left and the direction right, rather than the
    // direction being placed at an estimated character width after the symbol.
    // That estimate was wrong for any font it did not assume, so a long symbol
    // on a narrow image overlapped the edge and clipped.
    const svg = Buffer.from(
      `<svg width="${width}" height="${barHeight}" xmlns="http://www.w3.org/2000/svg">
         <rect width="100%" height="100%" fill="#0b1220" fill-opacity="0.92"/>
         <rect width="6" height="100%" fill="${accent}"/>
         <text x="${padding}" y="${Math.round(barHeight * 0.68)}"
               font-family="Helvetica, Arial, sans-serif" font-size="${fontSize}"
               font-weight="700" fill="#ffffff"
               textLength="${Math.min(width * 0.5, fontSize * brand.symbol.length * 0.7)}"
               lengthAdjust="spacingAndGlyphs">${escapeXml(brand.symbol)}</text>
         <text x="${width - padding}" y="${Math.round(barHeight * 0.68)}"
               text-anchor="end"
               font-family="Helvetica, Arial, sans-serif" font-size="${fontSize}"
               font-weight="700" fill="${accent}">${escapeXml(brand.direction)}</text>
       </svg>`,
    );

    return sharp(image)
      .composite([{ input: svg, gravity: 'north' }])
      .webp({ quality: 88 })
      .toBuffer();
  }
}

function escapeXml(s: string): string {
  return s.replace(/[<>&'"]/g, (c) =>
    ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' })[c]!,
  );
}
