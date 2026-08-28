import type { SignalStatus, SignalUpdateType, TradeDirection } from './domain';
import { computeSignalMetrics, type SignalLevels } from './pips';

/**
 * Presentation helpers shared by the Telegram bot and the mobile app.
 *
 * The Telegram message and the in-app signal card are rendered from this one
 * place, so a subscriber comparing the two never sees different numbers for
 * the same trade.
 */

export const STATUS_LABEL: Record<SignalStatus, string> = {
  DRAFT: 'Draft',
  PUBLISHED: 'Waiting for entry',
  ACTIVE: 'Running',
  BE_SET: 'Stop at break-even',
  TP1_HIT: 'TP1 hit',
  TP2_HIT: 'TP2 hit',
  TP3_HIT: 'TP3 hit',
  CLOSED_WIN: 'Closed in profit',
  CLOSED_BE: 'Closed at break-even',
  CLOSED_LOSS: 'Closed at a loss',
  CANCELLED: 'Cancelled',
};

export const UPDATE_LABEL: Record<SignalUpdateType, string> = {
  ENTRY_HIT: 'Entry filled',
  MOVED_TO_BE: 'Stop moved to break-even',
  TP1_HIT: 'TP1 reached',
  TP2_HIT: 'TP2 reached',
  TP3_HIT: 'TP3 reached',
  SL_HIT: 'Stop-loss hit',
  PARTIAL_CLOSE: 'Partial close',
  CLOSE_WIN: 'Closed in profit',
  CLOSE_LOSS: 'Closed at a loss',
  CANCELLED: 'Setup cancelled',
  COMMENT: 'Note',
};

export function directionEmoji(d: TradeDirection): string {
  return d === 'BUY' ? '\u{1F7E2}' : '\u{1F534}';
}

export function statusEmoji(s: SignalStatus): string {
  switch (s) {
    case 'CLOSED_WIN':
    case 'TP1_HIT':
    case 'TP2_HIT':
    case 'TP3_HIT':
      return '✅';
    case 'CLOSED_LOSS':
      return '❌';
    case 'CLOSED_BE':
      return '⚪';
    case 'BE_SET':
      return '\u{1F512}';
    case 'CANCELLED':
      return '\u{1F6AB}';
    default:
      return '⏳';
  }
}

/** Trim trailing zeros without losing meaningful precision on FX quotes. */
export function formatPrice(value: number): string {
  return Number(value.toFixed(5)).toString();
}

export interface SignalCardData extends SignalLevels {
  status: SignalStatus;
  timeframe: string;
  analysisText?: string;
}

/**
 * Render a signal as Telegram-flavoured Markdown.
 *
 * The bot *edits this same message* as the trade progresses rather than posting
 * a new one, so a channel reads as one live thread per trade instead of a wall
 * of fragments.
 */
export function formatSignalMarkdown(s: SignalCardData, opts: { locked?: boolean } = {}): string {
  const m = computeSignalMetrics(s);
  const head = `${directionEmoji(s.direction)} *${s.symbol}* — ${s.direction} (${s.timeframe})`;

  if (opts.locked) {
    return [
      head,
      '',
      '\u{1F512} Entry, targets and stop are for subscribers.',
      '',
      '_Open the app to unlock this signal._',
    ].join('\n');
  }

  const zone =
    s.entryLow === s.entryHigh
      ? formatPrice(s.entryLow)
      : `${formatPrice(s.entryLow)} – ${formatPrice(s.entryHigh)}`;

  const lines = [
    head,
    `${statusEmoji(s.status)} ${STATUS_LABEL[s.status]}`,
    '',
    `*Entry:* ${zone}`,
    `*Stop loss:* ${formatPrice(s.sl)}  (${m.slPips} pips)`,
  ];

  for (const t of m.targets) {
    lines.push(
      `*TP${t.level}:* ${formatPrice(t.price)}  (${t.pips} pips${t.rr ? `, ${t.rr}R` : ''})`,
    );
  }

  if (s.beTrigger != null) {
    lines.push(`*Move to break-even at:* ${formatPrice(s.beTrigger)}`);
  }

  if (s.analysisText) {
    lines.push('', s.analysisText);
  }

  lines.push('', '_Educational analysis only. Not financial advice. Trading carries risk._');
  return lines.join('\n');
}
