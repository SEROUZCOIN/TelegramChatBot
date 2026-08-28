-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('USER', 'COACH', 'ADMIN');

-- CreateEnum
CREATE TYPE "PlanCode" AS ENUM ('FREE', 'SIGNALS', 'NORMAL', 'PRO', 'ULTRA');

-- CreateEnum
CREATE TYPE "PlanInterval" AS ENUM ('MONTH', 'YEAR', 'ONE_TIME');

-- CreateEnum
CREATE TYPE "PaymentMode" AS ENUM ('EXTERNAL', 'IAP', 'BOTH');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('PENDING', 'ACTIVE', 'PAST_DUE', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "PaymentProviderCode" AS ENUM ('STRIPE', 'CRYPTO', 'BANK', 'IAP');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('PENDING', 'AWAITING_REVIEW', 'PAID', 'FAILED', 'REFUNDED');

-- CreateEnum
CREATE TYPE "TradeDirection" AS ENUM ('BUY', 'SELL');

-- CreateEnum
CREATE TYPE "OrderType" AS ENUM ('MARKET', 'LIMIT', 'STOP');

-- CreateEnum
CREATE TYPE "SignalStatus" AS ENUM ('DRAFT', 'PUBLISHED', 'ACTIVE', 'BE_SET', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS', 'CANCELLED');

-- CreateEnum
CREATE TYPE "SignalUpdateType" AS ENUM ('ENTRY_HIT', 'MOVED_TO_BE', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'SL_HIT', 'PARTIAL_CLOSE', 'CLOSE_WIN', 'CLOSE_LOSS', 'CANCELLED', 'COMMENT');

-- CreateEnum
CREATE TYPE "CourseLevel" AS ENUM ('BEGINNER', 'INTERMEDIATE', 'ADVANCED');

-- CreateEnum
CREATE TYPE "CoachingStatus" AS ENUM ('REQUESTED', 'SCHEDULED', 'LIVE', 'COMPLETED', 'CANCELLED', 'NO_SHOW');

-- CreateEnum
CREATE TYPE "AdSlot" AS ENUM ('FEED_INLINE', 'SIGNAL_DETAIL', 'COURSE_LIST', 'INTERSTITIAL', 'REWARDED');

-- CreateEnum
CREATE TYPE "LinkCategory" AS ENUM ('SOCIAL', 'CHANNEL', 'BROKER', 'SUPPORT', 'OTHER');

-- CreateEnum
CREATE TYPE "MediaType" AS ENUM ('IMAGE', 'VIDEO');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "role" "UserRole" NOT NULL DEFAULT 'USER',
    "locale" TEXT NOT NULL DEFAULT 'en',
    "avatarUrl" TEXT,
    "isBanned" BOOLEAN NOT NULL DEFAULT false,
    "riskDisclaimerAcceptedAt" TIMESTAMP(3),
    "riskDisclaimerVersion" TEXT,
    "telegramId" BIGINT,
    "telegramUsername" TEXT,
    "telegramLinkCode" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "pushToken" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "appVersion" TEXT NOT NULL DEFAULT '',
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "plans" (
    "id" TEXT NOT NULL,
    "code" "PlanCode" NOT NULL,
    "name" TEXT NOT NULL,
    "tagline" TEXT NOT NULL DEFAULT '',
    "priceCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "interval" "PlanInterval" NOT NULL DEFAULT 'MONTH',
    "paymentMode" "PaymentMode" NOT NULL DEFAULT 'EXTERNAL',
    "features" JSONB NOT NULL DEFAULT '[]',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "iapProductIdIos" TEXT,
    "iapProductIdAndroid" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "planId" TEXT NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'PENDING',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3),
    "cancelledAt" TIMESTAMP(3),
    "provider" "PaymentProviderCode",
    "externalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "planId" TEXT NOT NULL,
    "provider" "PaymentProviderCode" NOT NULL,
    "status" "PaymentStatus" NOT NULL DEFAULT 'PENDING',
    "amountCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "providerRef" TEXT,
    "reference" TEXT,
    "proofUrl" TEXT,
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "signals" (
    "id" TEXT NOT NULL,
    "symbol" TEXT NOT NULL,
    "direction" "TradeDirection" NOT NULL,
    "orderType" "OrderType" NOT NULL DEFAULT 'MARKET',
    "entryLow" DOUBLE PRECISION NOT NULL,
    "entryHigh" DOUBLE PRECISION NOT NULL,
    "sl" DOUBLE PRECISION NOT NULL,
    "tp1" DOUBLE PRECISION,
    "tp2" DOUBLE PRECISION,
    "tp3" DOUBLE PRECISION,
    "beTrigger" DOUBLE PRECISION,
    "pipSize" DOUBLE PRECISION,
    "timeframe" TEXT NOT NULL DEFAULT 'H1',
    "riskPercent" DOUBLE PRECISION,
    "analysisText" TEXT NOT NULL DEFAULT '',
    "slPips" DOUBLE PRECISION,
    "plannedRR" DOUBLE PRECISION,
    "resultPips" DOUBLE PRECISION,
    "status" "SignalStatus" NOT NULL DEFAULT 'DRAFT',
    "minPlan" "PlanCode" NOT NULL DEFAULT 'SIGNALS',
    "authorId" TEXT,
    "sourceKeyId" TEXT,
    "publishedAt" TIMESTAMP(3),
    "closedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "signals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "signal_updates" (
    "id" TEXT NOT NULL,
    "signalId" TEXT NOT NULL,
    "type" "SignalUpdateType" NOT NULL,
    "note" TEXT NOT NULL DEFAULT '',
    "price" DOUBLE PRECISION,
    "resultPips" DOUBLE PRECISION,
    "imageUrl" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "signal_updates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ingest_keys" (
    "id" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "keyHash" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastUsedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ingest_keys_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "media_assets" (
    "id" TEXT NOT NULL,
    "type" "MediaType" NOT NULL DEFAULT 'IMAGE',
    "provider" TEXT NOT NULL DEFAULT 'S3',
    "key" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "width" INTEGER,
    "height" INTEGER,
    "bytes" INTEGER,
    "brandedUrl" TEXT,
    "thumbnailUrl" TEXT,
    "signalId" TEXT,
    "uploadedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "media_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "courses" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "level" "CourseLevel" NOT NULL DEFAULT 'BEGINNER',
    "minPlan" "PlanCode" NOT NULL DEFAULT 'NORMAL',
    "coverUrl" TEXT,
    "isPublished" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "courses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "lessons" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "videoUid" TEXT,
    "durationSec" INTEGER NOT NULL DEFAULT 0,
    "order" INTEGER NOT NULL DEFAULT 0,
    "isFreePreview" BOOLEAN NOT NULL DEFAULT false,
    "attachments" JSONB NOT NULL DEFAULT '[]',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "lessons_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "lesson_progress" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "watchedSec" INTEGER NOT NULL DEFAULT 0,
    "completedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "lesson_progress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "coaching_sessions" (
    "id" TEXT NOT NULL,
    "studentId" TEXT NOT NULL,
    "coachId" TEXT,
    "status" "CoachingStatus" NOT NULL DEFAULT 'REQUESTED',
    "scheduledAt" TIMESTAMP(3) NOT NULL,
    "durationMin" INTEGER NOT NULL DEFAULT 60,
    "topic" TEXT NOT NULL DEFAULT '',
    "notes" TEXT NOT NULL DEFAULT '',
    "roomName" TEXT,
    "roomUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "coaching_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ad_placements" (
    "id" TEXT NOT NULL,
    "slot" "AdSlot" NOT NULL,
    "network" TEXT NOT NULL DEFAULT 'ADMOB',
    "unitIdIos" TEXT NOT NULL DEFAULT '',
    "unitIdAndroid" TEXT NOT NULL DEFAULT '',
    "isEnabled" BOOLEAN NOT NULL DEFAULT true,
    "minIntervalSec" INTEGER NOT NULL DEFAULT 60,
    "hideForPlans" "PlanCode"[] DEFAULT ARRAY['PRO', 'ULTRA']::"PlanCode"[],
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ad_placements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_links" (
    "id" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "icon" TEXT NOT NULL DEFAULT 'link',
    "category" "LinkCategory" NOT NULL DEFAULT 'SOCIAL',
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_links_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "link_clicks" (
    "id" TEXT NOT NULL,
    "linkId" TEXT NOT NULL,
    "userId" TEXT,
    "platform" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "link_clicks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "push_campaigns" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "deepLink" TEXT NOT NULL DEFAULT '',
    "audiencePlans" "PlanCode"[] DEFAULT ARRAY[]::"PlanCode"[],
    "scheduledAt" TIMESTAMP(3),
    "sentAt" TIMESTAMP(3),
    "sentCount" INTEGER NOT NULL DEFAULT 0,
    "failedCount" INTEGER NOT NULL DEFAULT 0,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "push_campaigns_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "telegram_messages" (
    "id" TEXT NOT NULL,
    "signalId" TEXT NOT NULL,
    "chatId" BIGINT NOT NULL,
    "messageId" INTEGER NOT NULL,
    "locked" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "telegram_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" TEXT NOT NULL,
    "actorId" TEXT,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityId" TEXT,
    "before" JSONB,
    "after" JSONB,
    "ip" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "settings" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "settings_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_telegramId_key" ON "users"("telegramId");

-- CreateIndex
CREATE UNIQUE INDEX "users_telegramLinkCode_key" ON "users"("telegramLinkCode");

-- CreateIndex
CREATE INDEX "users_role_idx" ON "users"("role");

-- CreateIndex
CREATE INDEX "users_createdAt_idx" ON "users"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "devices_pushToken_key" ON "devices"("pushToken");

-- CreateIndex
CREATE INDEX "devices_userId_idx" ON "devices"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "plans_code_key" ON "plans"("code");

-- CreateIndex
CREATE INDEX "subscriptions_userId_status_idx" ON "subscriptions"("userId", "status");

-- CreateIndex
CREATE INDEX "subscriptions_expiresAt_idx" ON "subscriptions"("expiresAt");

-- CreateIndex
CREATE INDEX "payments_userId_idx" ON "payments"("userId");

-- CreateIndex
CREATE INDEX "payments_status_idx" ON "payments"("status");

-- CreateIndex
CREATE INDEX "payments_providerRef_idx" ON "payments"("providerRef");

-- CreateIndex
CREATE INDEX "signals_status_publishedAt_idx" ON "signals"("status", "publishedAt");

-- CreateIndex
CREATE INDEX "signals_symbol_idx" ON "signals"("symbol");

-- CreateIndex
CREATE INDEX "signals_minPlan_idx" ON "signals"("minPlan");

-- CreateIndex
CREATE INDEX "signal_updates_signalId_createdAt_idx" ON "signal_updates"("signalId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ingest_keys_keyHash_key" ON "ingest_keys"("keyHash");

-- CreateIndex
CREATE INDEX "media_assets_signalId_idx" ON "media_assets"("signalId");

-- CreateIndex
CREATE UNIQUE INDEX "courses_slug_key" ON "courses"("slug");

-- CreateIndex
CREATE INDEX "courses_isPublished_sortOrder_idx" ON "courses"("isPublished", "sortOrder");

-- CreateIndex
CREATE INDEX "lessons_courseId_order_idx" ON "lessons"("courseId", "order");

-- CreateIndex
CREATE INDEX "lesson_progress_userId_idx" ON "lesson_progress"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "lesson_progress_userId_lessonId_key" ON "lesson_progress"("userId", "lessonId");

-- CreateIndex
CREATE INDEX "coaching_sessions_studentId_scheduledAt_idx" ON "coaching_sessions"("studentId", "scheduledAt");

-- CreateIndex
CREATE INDEX "coaching_sessions_coachId_scheduledAt_idx" ON "coaching_sessions"("coachId", "scheduledAt");

-- CreateIndex
CREATE UNIQUE INDEX "ad_placements_slot_key" ON "ad_placements"("slot");

-- CreateIndex
CREATE INDEX "app_links_isActive_sortOrder_idx" ON "app_links"("isActive", "sortOrder");

-- CreateIndex
CREATE INDEX "link_clicks_linkId_createdAt_idx" ON "link_clicks"("linkId", "createdAt");

-- CreateIndex
CREATE INDEX "push_campaigns_scheduledAt_idx" ON "push_campaigns"("scheduledAt");

-- CreateIndex
CREATE UNIQUE INDEX "telegram_messages_signalId_chatId_key" ON "telegram_messages"("signalId", "chatId");

-- CreateIndex
CREATE INDEX "audit_logs_entity_entityId_idx" ON "audit_logs"("entity", "entityId");

-- CreateIndex
CREATE INDEX "audit_logs_createdAt_idx" ON "audit_logs"("createdAt");

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_planId_fkey" FOREIGN KEY ("planId") REFERENCES "plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_planId_fkey" FOREIGN KEY ("planId") REFERENCES "plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signals" ADD CONSTRAINT "signals_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_updates" ADD CONSTRAINT "signal_updates_signalId_fkey" FOREIGN KEY ("signalId") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "media_assets" ADD CONSTRAINT "media_assets_signalId_fkey" FOREIGN KEY ("signalId") REFERENCES "signals"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lessons" ADD CONSTRAINT "lessons_courseId_fkey" FOREIGN KEY ("courseId") REFERENCES "courses"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lesson_progress" ADD CONSTRAINT "lesson_progress_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lesson_progress" ADD CONSTRAINT "lesson_progress_lessonId_fkey" FOREIGN KEY ("lessonId") REFERENCES "lessons"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_sessions" ADD CONSTRAINT "coaching_sessions_studentId_fkey" FOREIGN KEY ("studentId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_sessions" ADD CONSTRAINT "coaching_sessions_coachId_fkey" FOREIGN KEY ("coachId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "link_clicks" ADD CONSTRAINT "link_clicks_linkId_fkey" FOREIGN KEY ("linkId") REFERENCES "app_links"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "link_clicks" ADD CONSTRAINT "link_clicks_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "telegram_messages" ADD CONSTRAINT "telegram_messages_signalId_fkey" FOREIGN KEY ("signalId") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
