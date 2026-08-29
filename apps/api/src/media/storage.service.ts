import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { S3 } from 'aws-sdk';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { AppConfig } from '../config/configuration';

/**
 * Object storage for chart screenshots, course covers and payment proofs.
 *
 * Speaks S3, so the same code runs against MinIO locally, AWS S3, or Cloudflare
 * R2 in production. When no credentials are configured it falls back to the
 * local filesystem so a fresh checkout can upload images without any cloud
 * account at all.
 */
@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly s3: S3 | null;
  private readonly localRoot = join(process.cwd(), 'uploads');

  constructor(private readonly config: ConfigService<AppConfig, true>) {
    const cfg = this.config.get('s3', { infer: true });
    this.s3 =
      cfg.accessKeyId && cfg.secretAccessKey && cfg.endpoint
        ? new S3({
            endpoint: cfg.endpoint,
            region: cfg.region,
            accessKeyId: cfg.accessKeyId,
            secretAccessKey: cfg.secretAccessKey,
            s3ForcePathStyle: cfg.forcePathStyle,
            signatureVersion: 'v4',
          })
        : null;

    if (!this.s3) {
      this.logger.warn('S3 is not configured — falling back to local disk storage');
    }
  }

  async put(key: string, body: Buffer, contentType: string): Promise<string> {
    const cfg = this.config.get('s3', { infer: true });

    if (!this.s3) {
      const path = join(this.localRoot, key);
      await mkdir(join(path, '..'), { recursive: true });

      await writeFile(path, body);
      return `${this.config.get('apiPublicUrl', { infer: true })}/uploads/${key}`;
    }

    await this.s3
      .putObject({ Bucket: cfg.bucket, Key: key, Body: body, ContentType: contentType })
      .promise();

    return cfg.publicBaseUrl ? `${cfg.publicBaseUrl}/${key}` : `${cfg.endpoint}/${cfg.bucket}/${key}`;
  }
}
