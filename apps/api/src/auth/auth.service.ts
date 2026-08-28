import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
import { PrismaService } from '../common/prisma.service';
import type { AppConfig } from '../config/configuration';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService<AppConfig, true>,
  ) {}

  async register(input: {
    email: string;
    password: string;
    displayName: string;
    locale: string;
  }): Promise<TokenPair> {
    const email = input.email.toLowerCase().trim();
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) throw new ConflictException('An account with that email already exists');

    const user = await this.prisma.user.create({
      data: {
        email,
        passwordHash: await argon2.hash(input.password),
        displayName: input.displayName,
        locale: input.locale,
        // Single-use code the user pastes into the bot's /start to link Telegram.
        telegramLinkCode: randomBytes(6).toString('hex'),
      },
    });

    return this.issueTokens(user.id, user.email, user.role);
  }

  async login(email: string, password: string): Promise<TokenPair> {
    const user = await this.prisma.user.findUnique({
      where: { email: email.toLowerCase().trim() },
    });

    // Verify against a dummy hash when the account is missing so that a wrong
    // email and a wrong password take the same time to answer — otherwise the
    // endpoint tells an attacker which emails are registered.
    if (!user) {
      await argon2.verify(
        '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHRzb21lc2FsdA$RdescudvJCsgt3ub+b+dWRWJTmaaJObG',
        password,
      ).catch(() => undefined);
      throw new UnauthorizedException('Invalid email or password');
    }

    if (user.isBanned) throw new UnauthorizedException('This account has been suspended');
    if (user.deletedAt) throw new UnauthorizedException('This account has been deleted');

    const ok = await argon2.verify(user.passwordHash, password).catch(() => false);
    if (!ok) throw new UnauthorizedException('Invalid email or password');

    return this.issueTokens(user.id, user.email, user.role);
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    let payload: { sub: string; typ?: string };
    try {
      payload = await this.jwt.verifyAsync(refreshToken);
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
    if (payload.typ !== 'refresh') throw new UnauthorizedException('Not a refresh token');

    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.isBanned || user.deletedAt) {
      throw new UnauthorizedException('Account is no longer active');
    }

    return this.issueTokens(user.id, user.email, user.role);
  }

  /**
   * Records acceptance of the risk disclaimer.
   *
   * The version is stored alongside the timestamp: when the disclaimer text
   * changes, bumping RISK_DISCLAIMER_VERSION re-gates every user, and the audit
   * trail still shows which wording each of them actually agreed to.
   */
  async acceptDisclaimer(userId: string, version: string): Promise<{ acceptedAt: Date }> {
    const expected = this.config.get('riskDisclaimerVersion', { infer: true });
    if (version !== expected) {
      throw new BadRequestException(`Expected disclaimer version ${expected}`);
    }

    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { riskDisclaimerAcceptedAt: new Date(), riskDisclaimerVersion: version },
    });
    return { acceptedAt: user.riskDisclaimerAcceptedAt! };
  }

  private async issueTokens(id: string, email: string, role: string): Promise<TokenPair> {
    const jwtConfig = this.config.get('jwt', { infer: true });
    const [accessToken, refreshToken] = await Promise.all([
      this.jwt.signAsync({ sub: id, email, role, typ: 'access' }, { expiresIn: jwtConfig.accessTtl }),
      this.jwt.signAsync({ sub: id, email, role, typ: 'refresh' }, { expiresIn: jwtConfig.refreshTtl }),
    ]);
    return { accessToken, refreshToken };
  }
}
