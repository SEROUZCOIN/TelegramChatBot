import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
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

  app.setGlobalPrefix('api');
  // Request validation is per-route via ZodValidationPipe against the shared
  // schemas, so there is no global class-validator pipe here.
  app.enableCors({
    origin: [process.env.ADMIN_PUBLIC_URL ?? 'http://localhost:3001'],
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
