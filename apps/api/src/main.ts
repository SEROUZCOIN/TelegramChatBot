import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { join } from 'node:path';
import { AppModule } from './app.module';
import { PrismaService } from './common/prisma.service';

async function bootstrap(): Promise<void> {
  const adapter = new FastifyAdapter({
    // Webhook signatures cover the exact bytes received, so the raw body has to
    // survive JSON parsing or Stripe and NOWPayments can never be verified.
    bodyLimit: 15 * 1024 * 1024,
  });

  const app = await NestFactory.create<NestFastifyApplication>(AppModule, adapter, {
    rawBody: true,
  });

  await app.register(import('@fastify/multipart'), {
    limits: { fileSize: 12 * 1024 * 1024, files: 1 },
  });

  // Serve the local-disk storage fallback.
  //
  // When S3 is not configured, StorageService writes under ./uploads and hands
  // back /uploads/... URLs. Without this those URLs 404 — every chart uploaded
  // on a machine with no object store would render as a broken image.
  //
  // Deliberately scoped to `signals/`, not the whole uploads root: that
  // directory is public by nature, while anything else written there (payment
  // proofs above all) must never be reachable without authentication.
  //
  // This is the development path. In production set S3_* and let R2 or S3 serve
  // the bytes, so the API is not in the business of static files.
  await app.register(import('@fastify/static'), {
    root: join(process.cwd(), 'uploads', 'signals'),
    prefix: '/uploads/signals/',
    decorateReply: false,
  });

  app.setGlobalPrefix('api');
  // Request validation is per-route via ZodValidationPipe against the shared
  // schemas, so there is no global class-validator pipe here.
  // Comma-separated so one deployment can serve the admin panel, a web build
  // and a staging origin without a code change.
  app.enableCors({
    origin: (process.env.ADMIN_PUBLIC_URL ?? 'http://localhost:3001')
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    credentials: true,
  });

  const config = new DocumentBuilder()
    .setTitle('Trading Signals Platform API')
    .setDescription('Signals, academy, coaching, payments and admin')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, config));

  const prisma = app.get(PrismaService);
  await prisma.enableShutdownHooks(app);

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
  new Logger('Bootstrap').log(`API listening on http://localhost:${port}/api`);
}

void bootstrap();
