import { ForbiddenException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createSign } from 'node:crypto';
import type { AppConfig } from '../config/configuration';

/**
 * Signed playback tokens for Cloudflare Stream.
 *
 * The recorded video library *is* the NORMAL plan, so protecting it is not
 * optional. Possession of a Stream UID is enough to fetch the video, which is
 * why the UID never leaves the server: a client with entitlement exchanges a
 * lesson id for a short-lived signed token, and that token is what plays.
 */
@Injectable()
export class VideoService {
  private readonly logger = new Logger(VideoService.name);

  constructor(private readonly config: ConfigService<AppConfig, true>) {}

  isConfigured(): boolean {
    const cfg = this.config.get('stream', { infer: true });
    return Boolean(cfg.signingKeyId && cfg.signingKeyPem);
  }

  /**
   * Mint a playback token scoped to one video and one viewer.
   *
   * The token is deliberately short-lived: long enough to watch a lesson,
   * short enough that a leaked URL stops working quickly. The viewer id is
   * embedded so a shared link is traceable.
   */
  signPlaybackToken(videoUid: string, viewerId: string): { token: string; expiresAt: Date } {
    const cfg = this.config.get('stream', { infer: true });
    if (!this.isConfigured()) {
      throw new ServiceUnavailableException('Video playback is not configured');
    }

    const now = Math.floor(Date.now() / 1000);
    const exp = now + cfg.tokenTtlSec;

    const header = { alg: 'RS256', kid: cfg.signingKeyId };
    const payload = {
      sub: videoUid,
      kid: cfg.signingKeyId,
      exp,
      nbf: now - 30,
      // Surfaces in Cloudflare's analytics, so a leaked token traces back.
      accessRules: [{ type: 'any', action: 'allow' }],
      customerId: viewerId,
    };

    const encode = (o: unknown) =>
      Buffer.from(JSON.stringify(o)).toString('base64url');

    const signingInput = `${encode(header)}.${encode(payload)}`;
    const signature = createSign('RSA-SHA256')
      .update(signingInput)
      .sign(Buffer.from(cfg.signingKeyPem, 'base64').toString('utf8'), 'base64url');

    return { token: `${signingInput}.${signature}`, expiresAt: new Date(exp * 1000) };
  }

  playbackUrls(token: string): { hls: string; dash: string; thumbnail: string } {
    return {
      hls: `https://videodelivery.net/${token}/manifest/video.m3u8`,
      dash: `https://videodelivery.net/${token}/manifest/video.mpd`,
      thumbnail: `https://videodelivery.net/${token}/thumbnails/thumbnail.jpg`,
    };
  }

  assertEntitled(condition: boolean): void {
    if (!condition) throw new ForbiddenException('Your plan does not include this lesson');
  }
}
