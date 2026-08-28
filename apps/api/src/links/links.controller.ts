import { Body, Controller, Delete, Get, Param, Post, Put, Req } from '@nestjs/common';
import { appLinkSchema } from '@tsp/shared';
import { z } from 'zod';
import { CurrentUser, Public, Roles } from '../common/decorators';
import { ZodValidationPipe } from '../common/pipes/zod-validation.pipe';
import { PrismaService } from '../common/prisma.service';

@Controller('links')
export class LinksController {
  constructor(private readonly prisma: PrismaService) {}

  /** The clickable links hub shown in the app's profile tab. */
  @Public()
  @Get()
  list() {
    return this.prisma.appLink.findMany({
      where: { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { label: 'asc' }],
      select: { id: true, label: true, url: true, icon: true, category: true },
    });
  }

  /**
   * Records a tap, then hands back the destination.
   *
   * Tracking server-side rather than in the app means the click analytics in
   * the admin panel reflect real opens even when a link is shared onward, and
   * a link's destination can be changed later without shipping a new build.
   */
  @Post(':id/click')
  async click(
    @Param('id') id: string,
    @CurrentUser('id') userId: string,
    @Req() req: { headers: Record<string, string | undefined> },
  ) {
    const link = await this.prisma.appLink.findUnique({ where: { id } });
    if (!link || !link.isActive) return { url: null };

    await this.prisma.linkClick.create({
      data: {
        linkId: id,
        userId,
        platform: req.headers['x-client-platform'] ?? '',
      },
    });

    return { url: link.url };
  }
}

@Controller('admin/links')
@Roles('ADMIN')
export class AdminLinksController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list() {
    const links = await this.prisma.appLink.findMany({
      orderBy: { sortOrder: 'asc' },
      include: { _count: { select: { clicks: true } } },
    });
    return links.map(({ _count, ...l }) => ({ ...l, clickCount: _count.clicks }));
  }

  /** Click counts over a window, for the links analytics panel. */
  @Get('analytics')
  async analytics() {
    const since = new Date(Date.now() - 30 * 86_400_000);
    const grouped = await this.prisma.linkClick.groupBy({
      by: ['linkId'],
      where: { createdAt: { gte: since } },
      _count: { _all: true },
    });
    return grouped.map((g) => ({ linkId: g.linkId, clicks30d: g._count._all }));
  }

  @Post()
  create(@Body(new ZodValidationPipe(appLinkSchema)) body: z.infer<typeof appLinkSchema>) {
    return this.prisma.appLink.create({ data: body });
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body(new ZodValidationPipe(appLinkSchema.partial())) body: Partial<z.infer<typeof appLinkSchema>>,
  ) {
    return this.prisma.appLink.update({ where: { id }, data: body });
  }

  @Delete(':id')
  async remove(@Param('id') id: string) {
    await this.prisma.appLink.delete({ where: { id } });
    return { deleted: true };
  }
}
