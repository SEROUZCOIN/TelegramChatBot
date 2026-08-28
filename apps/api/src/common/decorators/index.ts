import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import type { UserRole } from '@prisma/client';

export const IS_PUBLIC_KEY = 'isPublic';
/** Marks a route as reachable without a bearer token. */
export const Public = (): MethodDecorator & ClassDecorator =>
  SetMetadata(IS_PUBLIC_KEY, true);

export const ROLES_KEY = 'roles';
export const Roles = (...roles: UserRole[]): MethodDecorator & ClassDecorator =>
  SetMetadata(ROLES_KEY, roles);

export interface AuthenticatedUser {
  id: string;
  email: string;
  role: UserRole;
}

export const CurrentUser = createParamDecorator(
  (data: keyof AuthenticatedUser | undefined, ctx: ExecutionContext) => {
    const req = ctx.switchToHttp().getRequest<{ user?: AuthenticatedUser }>();
    return data ? req.user?.[data] : req.user;
  },
);
