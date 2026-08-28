import { PrismaClient } from '@prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { EntitlementsService } from '../src/entitlements/entitlements.service';
import { SignalsService } from '../src/signals/signals.service';
import { PrismaService } from '../src/common/prisma.service';

/**
 * What a locked signal actually puts on the wire.
 *
 * This is the test that protects the business: the paid levels must be *absent*
 * from the serialised payload, not merely flagged for the client to hide. A
 * flag is a suggestion; absence is enforcement.
 */
describe('SignalsService presentation', () => {
  const prisma = new PrismaClient() as PrismaService;
  let signals: SignalsService;
  let freeUserId: string;
  let paidUserId: string;
  let signalId: string;

  beforeAll(async () => {
    const entitlements = new EntitlementsService(prisma);
    signals = new SignalsService(prisma, entitlements);

    const free = await prisma.user.create({
      data: { email: `free-${Date.now()}@test.invalid`, passwordHash: 'x', displayName: 'Free' },
    });
    const paid = await prisma.user.create({
      data: { email: `paid-${Date.now()}@test.invalid`, passwordHash: 'x', displayName: 'Paid' },
    });
    freeUserId = free.id;
    paidUserId = paid.id;

    const plan = await prisma.plan.findUniqueOrThrow({ where: { code: 'SIGNALS' } });
    await entitlements.grant({
      userId: paid.id,
      planId: plan.id,
      provider: 'STRIPE',
      durationDays: 30,
    });

    const signal = await signals.create(
      {
        symbol: 'EURUSD',
        direction: 'BUY',
        orderType: 'MARKET',
        entryLow: 1.08,
        entryHigh: 1.08,
        sl: 1.075,
        tp1: 1.085,
        tp2: 1.09,
        tp3: 1.095,
        beTrigger: 1.085,
        pipSize: null,
        timeframe: 'H1',
        riskPercent: 1,
        analysisText: 'Secret analysis that free users must not receive.',
        minPlan: 'SIGNALS',
        imageIds: [],
        publishNow: true,
      },
      { authorId: null },
    );
    signalId = signal.id;
  });

  afterAll(async () => {
    await prisma.signal.delete({ where: { id: signalId } }).catch(() => undefined);
    await prisma.user.deleteMany({ where: { id: { in: [freeUserId, paidUserId] } } });
    await prisma.$disconnect();
  });

  it('never serialises levels for a viewer without the plan', async () => {
    const view = await signals.findForUser(signalId, freeUserId);
    const raw = JSON.stringify(view);

    expect(view).toMatchObject({ locked: true, unlocked: false });

    // Not "not displayed" — genuinely not present in the bytes.
    for (const field of ['entryLow', 'entryHigh', 'sl', 'tp1', 'tp2', 'tp3', 'beTrigger']) {
      expect(raw).not.toContain(field);
    }
    expect(raw).not.toContain('Secret analysis');
    expect(raw).not.toContain('1.075');
  });

  it('still shows a locked viewer enough to want the upgrade', async () => {
    const view = (await signals.findForUser(signalId, freeUserId)) as Record<string, unknown>;
    expect(view.symbol).toBe('EURUSD');
    expect(view.direction).toBe('BUY');
    expect(view.publishedAt).toBeTruthy();
  });

  it('serves the full signal to a subscriber, with derived metrics', async () => {
    const view = (await signals.findForUser(signalId, paidUserId)) as Record<string, never>;
    expect(view.locked).toBe(false);
    expect(view.sl).toBe(1.075);
    expect(view.analysisText).toContain('Secret analysis');

    const metrics = view.metrics as unknown as {
      slPips: number;
      maxRR: number;
      targets: Array<{ pips: number; rr: number }>;
    };
    expect(metrics.slPips).toBe(50);
    expect(metrics.targets.map((t) => t.pips)).toEqual([50, 100, 150]);
    expect(metrics.maxRR).toBe(3);
  });

  it('rejects levels that do not make sense before anything is stored', async () => {
    const before = await prisma.signal.count();

    await expect(
      signals.create(
        {
          symbol: 'EURUSD',
          direction: 'BUY',
          orderType: 'MARKET',
          entryLow: 1.08,
          entryHigh: 1.08,
          // Stop above entry on a BUY: almost always a typo, never published.
          sl: 1.09,
          tp1: 1.1,
          tp2: null,
          tp3: null,
          beTrigger: null,
          pipSize: null,
          timeframe: 'H1',
          riskPercent: null,
          analysisText: '',
          minPlan: 'SIGNALS',
          imageIds: [],
          publishNow: true,
        },
        { authorId: null },
      ),
    ).rejects.toThrow(/invalid signal levels/i);

    expect(await prisma.signal.count()).toBe(before);
  });

  it('scores a stop-out after break-even as a scratch, not a loss', async () => {
    const signal = await signals.create(
      {
        symbol: 'GBPUSD',
        direction: 'BUY',
        orderType: 'MARKET',
        entryLow: 1.27,
        entryHigh: 1.27,
        sl: 1.265,
        tp1: 1.275,
        tp2: null,
        tp3: null,
        beTrigger: 1.275,
        pipSize: null,
        timeframe: 'H1',
        riskPercent: null,
        analysisText: '',
        minPlan: 'SIGNALS',
        imageIds: [],
        publishNow: true,
      },
      { authorId: null },
    );

    await signals.addUpdate(signal.id, { type: 'ENTRY_HIT', note: '', price: 1.27, imageId: null }, null);
    await signals.addUpdate(signal.id, { type: 'MOVED_TO_BE', note: '', price: null, imageId: null }, null);
    const closed = await signals.addUpdate(
      signal.id,
      { type: 'SL_HIT', note: '', price: 1.27, imageId: null },
      null,
    );

    expect(closed.status).toBe('CLOSED_BE');
    expect(closed.resultPips).toBe(0);

    await prisma.signal.delete({ where: { id: signal.id } });
  });

  it('refuses to reopen a closed signal', async () => {
    const signal = await signals.create(
      {
        symbol: 'USDJPY',
        direction: 'SELL',
        orderType: 'MARKET',
        entryLow: 150,
        entryHigh: 150,
        sl: 150.5,
        tp1: 149.5,
        tp2: null,
        tp3: null,
        beTrigger: null,
        pipSize: null,
        timeframe: 'H1',
        riskPercent: null,
        analysisText: '',
        minPlan: 'SIGNALS',
        imageIds: [],
        publishNow: true,
      },
      { authorId: null },
    );

    await signals.addUpdate(signal.id, { type: 'ENTRY_HIT', note: '', price: 150, imageId: null }, null);
    const lost = await signals.addUpdate(
      signal.id,
      { type: 'SL_HIT', note: '', price: 150.5, imageId: null },
      null,
    );
    expect(lost.status).toBe('CLOSED_LOSS');
    // USDJPY quotes to 3dp, so 50 pips of loss rather than 5000.
    expect(lost.resultPips).toBe(-50);

    await expect(
      signals.addUpdate(signal.id, { type: 'TP1_HIT', note: '', price: null, imageId: null }, null),
    ).rejects.toThrow(/cannot apply/i);

    await prisma.signal.delete({ where: { id: signal.id } });
  });
});
