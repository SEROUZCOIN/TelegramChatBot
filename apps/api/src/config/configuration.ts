/**
 * Typed view over the environment. Every module reads config through here so
 * a missing variable surfaces at boot rather than at the first request.
 */
export interface AppConfig {
  env: string;
  port: number;
  apiPublicUrl: string;
  adminPublicUrl: string;
  deepLinkScheme: string;
  jwt: { secret: string; accessTtl: string; refreshTtl: string };
  riskDisclaimerVersion: string;
  s3: {
    endpoint: string;
    region: string;
    bucket: string;
    accessKeyId: string;
    secretAccessKey: string;
    publicBaseUrl: string;
    forcePathStyle: boolean;
  };
  stream: {
    accountId: string;
    apiToken: string;
    signingKeyId: string;
    signingKeyPem: string;
    tokenTtlSec: number;
  };
  stripe: { secretKey: string; webhookSecret: string; successUrl: string; cancelUrl: string };
  crypto: { apiKey: string; ipnSecret: string };
  bank: { instructions: string };
  revenueCat: { apiKey: string; webhookSecret: string };
  daily: { apiKey: string; domain: string };
  telegram: {
    botToken: string;
    publicChannelId: string;
    webhookSecret: string;
    usePolling: boolean;
  };
  expo: { accessToken: string };
  seed: { adminEmail: string; adminPassword: string };
}

const bool = (v: string | undefined, fallback = false): boolean =>
  v === undefined ? fallback : /^(1|true|yes)$/i.test(v);

const int = (v: string | undefined, fallback: number): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

export default (): AppConfig => ({
  env: process.env.NODE_ENV ?? 'development',
  port: int(process.env.PORT, 3000),
  apiPublicUrl: process.env.API_PUBLIC_URL ?? 'http://localhost:3000',
  adminPublicUrl: process.env.ADMIN_PUBLIC_URL ?? 'http://localhost:3001',
  deepLinkScheme: process.env.APP_DEEP_LINK_SCHEME ?? 'tsp',
  jwt: {
    secret: process.env.JWT_SECRET ?? 'dev-only-insecure-secret',
    accessTtl: process.env.JWT_ACCESS_TTL ?? '15m',
    refreshTtl: process.env.JWT_REFRESH_TTL ?? '30d',
  },
  riskDisclaimerVersion: process.env.RISK_DISCLAIMER_VERSION ?? '2026-01',
  s3: {
    endpoint: process.env.S3_ENDPOINT ?? '',
    region: process.env.S3_REGION ?? 'auto',
    bucket: process.env.S3_BUCKET ?? 'tsp-media',
    accessKeyId: process.env.S3_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? '',
    publicBaseUrl: process.env.S3_PUBLIC_BASE_URL ?? '',
    forcePathStyle: bool(process.env.S3_FORCE_PATH_STYLE, true),
  },
  stream: {
    accountId: process.env.CF_ACCOUNT_ID ?? '',
    apiToken: process.env.CF_STREAM_API_TOKEN ?? '',
    signingKeyId: process.env.CF_STREAM_SIGNING_KEY_ID ?? '',
    signingKeyPem: process.env.CF_STREAM_SIGNING_KEY_PEM ?? '',
    tokenTtlSec: int(process.env.CF_STREAM_TOKEN_TTL_SEC, 7200),
  },
  stripe: {
    secretKey: process.env.STRIPE_SECRET_KEY ?? '',
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET ?? '',
    successUrl: process.env.STRIPE_SUCCESS_URL ?? 'tsp://checkout/success',
    cancelUrl: process.env.STRIPE_CANCEL_URL ?? 'tsp://checkout/cancel',
  },
  crypto: {
    apiKey: process.env.NOWPAYMENTS_API_KEY ?? '',
    ipnSecret: process.env.NOWPAYMENTS_IPN_SECRET ?? '',
  },
  bank: { instructions: process.env.BANK_TRANSFER_INSTRUCTIONS ?? '' },
  revenueCat: {
    apiKey: process.env.REVENUECAT_API_KEY ?? '',
    webhookSecret: process.env.REVENUECAT_WEBHOOK_SECRET ?? '',
  },
  daily: { apiKey: process.env.DAILY_API_KEY ?? '', domain: process.env.DAILY_DOMAIN ?? '' },
  telegram: {
    botToken: process.env.TELEGRAM_BOT_TOKEN ?? '',
    publicChannelId: process.env.TELEGRAM_PUBLIC_CHANNEL_ID ?? '',
    webhookSecret: process.env.TELEGRAM_WEBHOOK_SECRET ?? '',
    usePolling: bool(process.env.TELEGRAM_USE_POLLING, true),
  },
  expo: { accessToken: process.env.EXPO_ACCESS_TOKEN ?? '' },
  seed: {
    adminEmail: process.env.SEED_ADMIN_EMAIL ?? 'admin@example.com',
    adminPassword: process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!',
  },
});
