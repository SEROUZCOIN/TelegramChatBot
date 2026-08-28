import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY, type AuthenticatedUser } from '../decorators';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (isPublic) return true;

    const req = ctx.switchToHttp().getRequest<{
      headers: Record<string, string | undefined>;
      user?: AuthenticatedUser;
    }>();

    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || !token) {
      throw new UnauthorizedException('Missing bearer token');
    }

    try {
      const payload = await this.jwt.verifyAsync<{
        sub: string;
        email: string;
        role: AuthenticatedUser['role'];
        typ?: string;
      }>(token);

      // Refresh tokens must not be usable as access tokens: they are long-lived
      // by design, so accepting one here would hand out a 30-day session.
      if (payload.typ === 'refresh') {
        throw new UnauthorizedException('Refresh token cannot be used for access');
      }

      req.user = { id: payload.sub, email: payload.email, role: payload.role };
      return true;
    } catch (err) {
      if (err instanceof UnauthorizedException) throw err;
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
