import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';
import { randomBytes, createHash } from 'node:crypto';

const prisma = new PrismaClient();

/**
 * Seeds the four commercial plans, an admin account, the ad slots, and a
 * worked example signal.
 *
 * The `paymentMode` values encode the platform's payment strategy directly:
 * everything runs on external rails, which keeps roughly 97% of revenue.
 * If App Review objects to the NORMAL tier selling recorded video outside
 * in-app purchase (guideline 3.1.1), that one row becomes IAP — no code change.
 */
async function main(): Promise<void> {
  const plans = [
    {
      code: 'SIGNALS' as const,
      name: 'Signals',
      tagline: 'Live trade ideas with full entry, targets and stop',
      priceCents: 7_500,
      interval: 'MONTH' as const,
      sortOrder: 1,
      features: [
        'Every signal with entry zone, TP1/TP2/TP3 and stop loss',
        'Live updates: entry filled, stop to break-even, targets hit',
        'Chart screenshot with every setup',
        'Push and Telegram delivery',
        'Full public performance record',
      ],
    },
    {
      code: 'NORMAL' as const,
      name: 'Normal',
      tagline: 'The full recorded video library, yours to work through',
      priceCents: 10_000,
      interval: 'MONTH' as const,
      sortOrder: 2,
      features: [
        'Everything in Signals',
        'Complete recorded video course library',
        'New lessons added monthly',
        'Progress tracking across every course',
      ],
    },
    {
      code: 'PRO' as const,
      name: 'Pro',
      tagline: 'One-to-one mentoring, taught live',
      priceCents: 150_000,
      // One-time: a coaching package is bought once, not billed monthly.
      interval: 'ONE_TIME' as const,
      sortOrder: 3,
      features: [
        'Everything in Normal',
        'Live one-to-one sessions with screen share',
        'Your trading plan reviewed personally',
        'Direct message access between sessions',
        'No ads, ever',
      ],
    },
    {
      code: 'ULTRA' as const,
      name: 'Ultra',
      tagline: 'Beginner to professional, start to finish',
      priceCents: 500_000,
      interval: 'ONE_TIME' as const,
      sortOrder: 4,
      features: [
        'Everything in Pro',
        'Structured beginner-to-professional curriculum',
        'Extended one-to-one mentorship programme',
        'Personal risk and psychology coaching',
        'Lifetime access to all future course material',
        'No ads, ever',
      ],
    },
  ];

  for (const plan of plans) {
    await prisma.plan.upsert({
      where: { code: plan.code },
      create: { ...plan, paymentMode: 'EXTERNAL', features: plan.features },
      update: {
        name: plan.name,
        tagline: plan.tagline,
        priceCents: plan.priceCents,
        interval: plan.interval,
        sortOrder: plan.sortOrder,
        features: plan.features,
      },
    });
  }

  // FREE is not purchasable; it exists so entitlement lookups always resolve.
  await prisma.plan.upsert({
    where: { code: 'FREE' },
    create: {
      code: 'FREE',
      name: 'Free',
      tagline: 'Browse the record, see what a signal looks like',
      priceCents: 0,
      interval: 'MONTH',
      sortOrder: 0,
      isActive: false,
      features: ['Public performance record', 'Free preview lessons', 'Locked signal previews'],
    },
    update: {},
  });

  const adminEmail = (process.env.SEED_ADMIN_EMAIL ?? 'admin@example.com').toLowerCase();
  const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!';

  const admin = await prisma.user.upsert({
    where: { email: adminEmail },
    create: {
      email: adminEmail,
      passwordHash: await argon2.hash(adminPassword),
      displayName: 'Administrator',
      role: 'ADMIN',
      riskDisclaimerAcceptedAt: new Date(),
      riskDisclaimerVersion: process.env.RISK_DISCLAIMER_VERSION ?? '2026-01',
      telegramLinkCode: randomBytes(6).toString('hex'),
    },
    update: { role: 'ADMIN' },
  });

  // Paid tiers must never see ads; that suppression is enforced server-side.
  const adSlots = [
    { slot: 'FEED_INLINE' as const, minIntervalSec: 90 },
    { slot: 'SIGNAL_DETAIL' as const, minIntervalSec: 120 },
    { slot: 'COURSE_LIST' as const, minIntervalSec: 120 },
    { slot: 'INTERSTITIAL' as const, minIntervalSec: 300 },
    { slot: 'REWARDED' as const, minIntervalSec: 0 },
  ];

  for (const ad of adSlots) {
    await prisma.adPlacement.upsert({
      where: { slot: ad.slot },
      create: {
        ...ad,
        network: 'ADMOB',
        isEnabled: false, // stays off until real AdMob unit ids are configured
        hideForPlans: ['PRO', 'ULTRA'],
      },
      update: {},
    });
  }

  const links = [
    { label: 'Telegram channel', url: 'https://t.me/example', icon: 'send', category: 'CHANNEL' as const, sortOrder: 1 },
    { label: 'YouTube', url: 'https://youtube.com/@example', icon: 'youtube', category: 'SOCIAL' as const, sortOrder: 2 },
    { label: 'Instagram', url: 'https://instagram.com/example', icon: 'instagram', category: 'SOCIAL' as const, sortOrder: 3 },
    { label: 'Support', url: 'https://t.me/example_support', icon: 'help-circle', category: 'SUPPORT' as const, sortOrder: 4 },
  ];

  for (const link of links) {
    const existing = await prisma.appLink.findFirst({ where: { label: link.label } });
    if (!existing) await prisma.appLink.create({ data: link });
  }

  // An ingest key for the MT5 bridge. Printed once; only the hash is stored.
  const existingKey = await prisma.ingestKey.findFirst({ where: { label: 'MT5 bridge (seed)' } });
  let ingestKeyPlain: string | null = null;
  if (!existingKey) {
    ingestKeyPlain = randomBytes(24).toString('hex');
    await prisma.ingestKey.create({
      data: {
        label: 'MT5 bridge (seed)',
        keyHash: createHash('sha256').update(ingestKeyPlain).digest('hex'),
      },
    });
  }

  const course = await prisma.course.upsert({
    where: { slug: 'foundations' },
    create: {
      title: 'Foundations: how markets actually move',
      slug: 'foundations',
      description:
        'Start here. Market structure, risk per trade, and how to read a setup before you ever place one.',
      level: 'BEGINNER',
      minPlan: 'NORMAL',
      isPublished: true,
      sortOrder: 1,
    },
    update: {},
  });

  const lessonCount = await prisma.lesson.count({ where: { courseId: course.id } });
  if (lessonCount === 0) {
    await prisma.lesson.createMany({
      data: [
        {
          courseId: course.id,
          title: 'What a trading plan is for',
          description: 'Why the plan exists before the trade does.',
          order: 1,
          durationSec: 720,
          // The funnel: one lesson plays on any tier, including free.
          isFreePreview: true,
        },
        {
          courseId: course.id,
          title: 'Risk per trade, and why it is fixed',
          description: 'Position sizing from the stop, not from hope.',
          order: 2,
          durationSec: 960,
        },
        {
          courseId: course.id,
          title: 'Reading market structure',
          description: 'Higher highs, lower lows, and where a setup invalidates.',
          order: 3,
          durationSec: 1140,
        },
      ],
    });
  }

  // A worked example so a fresh install has something real in the feed.
  const sampleExists = await prisma.signal.findFirst({ where: { analysisText: { contains: 'Example signal' } } });
  if (!sampleExists) {
    const signal = await prisma.signal.create({
      data: {
        symbol: 'EURUSD',
        direction: 'BUY',
        orderType: 'LIMIT',
        entryLow: 1.079,
        entryHigh: 1.0810,
        sl: 1.0750,
        tp1: 1.0850,
        tp2: 1.0900,
        tp3: 1.0950,
        beTrigger: 1.0850,
        timeframe: 'H4',
        riskPercent: 1,
        analysisText:
          'Example signal. Price returned to the H4 demand zone that produced the last impulse. ' +
          'Entry across the zone, stop below the swing low, first target at the prior high. ' +
          'Move the stop to break-even once TP1 fills.',
        minPlan: 'SIGNALS',
        slPips: 50,
        plannedRR: 3,
        status: 'PUBLISHED',
        publishedAt: new Date(),
        authorId: admin.id,
      },
    });

    await prisma.signalUpdate.createMany({
      data: [
        { signalId: signal.id, type: 'ENTRY_HIT', note: 'Filled across the zone.', price: 1.08 },
        { signalId: signal.id, type: 'TP1_HIT', note: 'First target reached.', price: 1.085, resultPips: 50 },
        { signalId: signal.id, type: 'MOVED_TO_BE', note: 'Stop pulled to entry. Risk is off the table.' },
      ],
    });

    await prisma.signal.update({ where: { id: signal.id }, data: { status: 'TP1_HIT' } });
  }

  console.log('Seed complete.');
  console.log(`  Admin login: ${adminEmail} / ${adminPassword}`);
  if (ingestKeyPlain) {
    console.log(`  MT5 ingest key (shown once, store it now): ${ingestKeyPlain}`);
  }
  console.log('  Plans: SIGNALS $75/mo, NORMAL $100/mo, PRO $1500 one-time, ULTRA $5000 one-time');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
