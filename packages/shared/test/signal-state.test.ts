import { describe, expect, it } from 'vitest';
import {
  availableUpdateActions,
  canApplyUpdate,
  canTransition,
  isTerminal,
  resolveProgress,
  resolveStatus,
} from '../src/signal-state';

const published = (updates: Parameters<typeof resolveStatus>[0]['updates']) =>
  resolveStatus({ published: true, updates });

describe('resolveStatus', () => {
  it('is DRAFT before publishing and PUBLISHED after, with no updates', () => {
    expect(resolveStatus({ published: false, updates: [] })).toBe('DRAFT');
    expect(resolveStatus({ published: true, updates: [] })).toBe('PUBLISHED');
  });

  it('walks the happy path to TP3', () => {
    expect(published(['ENTRY_HIT'])).toBe('ACTIVE');
    expect(published(['ENTRY_HIT', 'MOVED_TO_BE'])).toBe('BE_SET');
    expect(published(['ENTRY_HIT', 'MOVED_TO_BE', 'TP1_HIT'])).toBe('TP1_HIT');
    expect(published(['ENTRY_HIT', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT'])).toBe('TP3_HIT');
  });

  it('scores a stop-out after break-even as a scratch, not a loss', () => {
    expect(published(['ENTRY_HIT', 'MOVED_TO_BE', 'SL_HIT'])).toBe('CLOSED_BE');
  });

  it('scores a stop-out before break-even as a loss', () => {
    expect(published(['ENTRY_HIT', 'SL_HIT'])).toBe('CLOSED_LOSS');
  });

  it('keeps break-even protection after a target is reached', () => {
    // TP1 advances the visible status past BE_SET, but the stop is still at
    // break-even, so a later stop-out must not be recorded as a loss.
    expect(published(['ENTRY_HIT', 'MOVED_TO_BE', 'TP1_HIT', 'SL_HIT'])).toBe('CLOSED_BE');
  });

  it('never regresses progress on out-of-order reports', () => {
    expect(published(['ENTRY_HIT', 'TP2_HIT', 'TP1_HIT'])).toBe('TP2_HIT');
  });

  it('infers entry from any progress update when ENTRY_HIT was never sent', () => {
    expect(published(['TP1_HIT'])).toBe('TP1_HIT');
    expect(resolveProgress({ published: true, updates: ['TP1_HIT'] }).entered).toBe(true);
  });

  it('ignores everything after a close', () => {
    expect(published(['ENTRY_HIT', 'CLOSE_WIN', 'SL_HIT', 'TP3_HIT'])).toBe('CLOSED_WIN');
  });

  it('treats COMMENT and PARTIAL_CLOSE as timeline-only', () => {
    expect(published(['ENTRY_HIT', 'COMMENT', 'PARTIAL_CLOSE'])).toBe('ACTIVE');
  });

  it('cancels from a pre-entry state', () => {
    expect(published(['CANCELLED'])).toBe('CANCELLED');
  });
});

describe('canTransition', () => {
  it('allows publishing a draft but not skipping to active', () => {
    expect(canTransition('DRAFT', 'PUBLISHED')).toBe(true);
    expect(canTransition('DRAFT', 'ACTIVE')).toBe(false);
  });

  it('locks every terminal status', () => {
    for (const s of ['CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS', 'CANCELLED'] as const) {
      expect(isTerminal(s)).toBe(true);
      expect(canTransition(s, 'ACTIVE')).toBe(false);
    }
  });

  it('refuses to reopen a closed signal via TP3', () => {
    expect(canTransition('CLOSED_LOSS', 'TP3_HIT')).toBe(false);
  });
});

describe('canApplyUpdate', () => {
  it('refuses progress updates on a closed signal', () => {
    expect(canApplyUpdate('CLOSED_WIN', 'TP2_HIT')).toBe(false);
    expect(canApplyUpdate('CANCELLED', 'ENTRY_HIT')).toBe(false);
  });

  it('still allows a post-mortem comment on a closed signal', () => {
    expect(canApplyUpdate('CLOSED_LOSS', 'COMMENT')).toBe(true);
  });

  it('only allows cancelling an unpublished draft', () => {
    expect(canApplyUpdate('DRAFT', 'CANCELLED')).toBe(true);
    expect(canApplyUpdate('DRAFT', 'ENTRY_HIT')).toBe(false);
  });

  it('offers the admin console only legal actions', () => {
    expect(availableUpdateActions('CLOSED_WIN')).toEqual(['COMMENT']);
    expect(availableUpdateActions('ACTIVE')).toContain('MOVED_TO_BE');
    expect(availableUpdateActions('DRAFT')).toEqual(['CANCELLED', 'COMMENT']);
  });
});
