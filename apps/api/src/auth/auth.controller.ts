import { Body, Controller, Get, Post, Req } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { acceptDisclaimerSchema, loginSchema, registerSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Public } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { AuthService } from './auth.service';
import { AuditService } from '../common/audit.service';
import type { AppConfig } from '../config/configuration';
import { RISK_DISCLAIMER_TEXT } from './disclaimer.text';

const refreshSchema = z.object({ refreshToken: z.string().min(10) });

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly audit: AuditService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {}

  @Public()
  @Post('register')
  register(@Body(new ZodValidationPipe(registerSchema)) body: z.infer<typeof registerSchema>) {
    return this.auth.register(body);
  }

  @Public()
  @Post('login')
  login(@Body(new ZodValidationPipe(loginSchema)) body: z.infer<typeof loginSchema>) {
    return this.auth.login(body.email, body.password);
  }

  @Public()
  @Post('refresh')
  refresh(@Body(new ZodValidationPipe(refreshSchema)) body: z.infer<typeof refreshSchema>) {
    return this.auth.refresh(body.refreshToken);
  }

  /**
   * The disclaimer the app must show before anything else. Served from the API
   * so the wording can be corrected without shipping a new binary through
   * two app store review queues.
   */
  @Public()
  @Get('disclaimer')
  disclaimer() {
    return {
      version: this.config.get('riskDisclaimerVersion', { infer: true }),
      text: RISK_DISCLAIMER_TEXT,
    };
  }

  @Post('disclaimer/accept')
  async accept(
    @CurrentUser('id') userId: string,
    @Body(new ZodValidationPipe(acceptDisclaimerSchema))
    body: z.infer<typeof acceptDisclaimerSchema>,
    @Req() req: { ip?: string },
  ) {
    const result = await this.auth.acceptDisclaimer(userId, body.version);
    await this.audit.record({
      actorId: userId,
      action: 'disclaimer.accept',
      entity: 'User',
      entityId: userId,
      after: { version: body.version },
      ip: req.ip ?? null,
    });
    return result;
  }
}
