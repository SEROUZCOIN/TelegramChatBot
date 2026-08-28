import type { SignalStatus, SignalUpdateType } from './domain';

/**
 * Signal lifecycle.
 *
 *   DRAFT -> PUBLISHED -> ACTIVE -> BE_SET -> TP1_HIT -> TP2_HIT -> TP3_HIT
 *                                      \                              |
 *                                       \-> SL_HIT                    v
 *                                            |                   CLOSED_WIN
 *                                            v
 *                              CLOSED_LOSS / CLOSED_BE
 *
 * The status is *derived*, never stored independently: `resolveStatus` folds
 * the append-only update ledger into a status. That makes drift between the
 * timeline a subscriber reads and the badge they see structurally impossible —
 * which matters in a product whose credibility rests on an honest trade record.
 */

/** Statuses from which no further transition is possible. */
export const TERMINAL_STATUSES: readonly SignalStatus[] = [
  'CLOSED_WIN',
  'CLOSED_BE',
  'CLOSED_LOSS',
  'CANCELLED',
];

export function isTerminal(status: SignalStatus): boolean {
  return TERMINAL_STATUSES.includes(status);
}

/** Legal status edges. Validates direct status writes such as publishing. */
const TRANSITIONS: Record<SignalStatus, readonly SignalStatus[]> = {
  DRAFT: ['PUBLISHED', 'CANCELLED'],
  PUBLISHED: ['ACTIVE', 'CANCELLED'],
  ACTIVE: ['BE_SET', 'TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'CLOSED_WIN', 'CLOSED_LOSS', 'CANCELLED'],
  BE_SET: ['TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'CLOSED_WIN', 'CLOSED_BE'],
  TP1_HIT: ['BE_SET', 'TP2_HIT', 'TP3_HIT', 'CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS'],
  TP2_HIT: ['BE_SET', 'TP3_HIT', 'CLOSED_WIN', 'CLOSED_BE', 'CLOSED_LOSS'],
  TP3_HIT: ['CLOSED_WIN'],
  CLOSED_WIN: [],
  CLOSED_BE: [],
  CLOSED_LOSS: [],
  CANCELLED: [],
};

export function canTransition(from: SignalStatus, to: SignalStatus): boolean {
  return TRANSITIONS[from].includes(to);
}

export function allowedTransitions(from: SignalStatus): readonly SignalStatus[] {
  return TRANSITIONS[from];
}

/** Accumulated facts derived from the ledger. */
export interface SignalProgress {
  published: boolean;
  entered: boolean;
  /** Stop-loss moved to break-even. Decides how an SL hit is scored. */
  beSet: boolean;
  /** Highest take-profit reached: 0 = none, 3 = TP3. */
  maxTp: 0 | 1 | 2 | 3;
  terminal: SignalStatus | null;
  status: SignalStatus;
}

const TP_STATUS: Record<1 | 2 | 3, SignalStatus> = {
  1: 'TP1_HIT',
  2: 'TP2_HIT',
  3: 'TP3_HIT',
};

/**
 * Fold the update ledger into the signal's progress and status.
 *
 * Updates apply in order and never regress progress — a TP2 fill followed by a
 * stray TP1 report still reads as TP2. COMMENT and PARTIAL_CLOSE appear in the
 * timeline without moving the status. Nothing after a close counts.
 */
export function resolveProgress(input: {
  published: boolean;
  updates: readonly SignalUpdateType[];
}): SignalProgress {
  let entered = false;
  let beSet = false;
  let maxTp: 0 | 1 | 2 | 3 = 0;
  let terminal: SignalStatus | null = null;

  for (const u of input.updates) {
    if (terminal) break;

    switch (u) {
      case 'ENTRY_HIT':
        entered = true;
        break;
      case 'MOVED_TO_BE':
        entered = true;
        beSet = true;
        break;
      case 'TP1_HIT':
        entered = true;
        if (maxTp < 1) maxTp = 1;
        break;
      case 'TP2_HIT':
        entered = true;
        if (maxTp < 2) maxTp = 2;
        break;
      case 'TP3_HIT':
        entered = true;
        maxTp = 3;
        break;
      case 'SL_HIT':
        // The distinction that keeps the public win-rate honest: a stop taken
        // out *after* it was moved to break-even is a scratch trade, not a
        // loss. Scoring it as a loss understates the record, scoring it as a
        // win overstates it, so it gets its own outcome.
        terminal = beSet ? 'CLOSED_BE' : 'CLOSED_LOSS';
        break;
      case 'CLOSE_WIN':
        terminal = 'CLOSED_WIN';
        break;
      case 'CLOSE_LOSS':
        terminal = 'CLOSED_LOSS';
        break;
      case 'CANCELLED':
        terminal = 'CANCELLED';
        break;
      case 'PARTIAL_CLOSE':
      case 'COMMENT':
        break;
    }
  }

  const status: SignalStatus = terminal
    ? terminal
    : maxTp > 0
      ? TP_STATUS[maxTp as 1 | 2 | 3]
      : beSet
        ? 'BE_SET'
        : entered
          ? 'ACTIVE'
          : input.published
            ? 'PUBLISHED'
            : 'DRAFT';

  return { published: input.published, entered, beSet, maxTp, terminal, status };
}

export function resolveStatus(input: {
  published: boolean;
  updates: readonly SignalUpdateType[];
}): SignalStatus {
  return resolveProgress(input).status;
}

/**
 * Whether an update may be appended to a signal in the given status.
 * COMMENT is always allowed so a closed trade can still carry a post-mortem;
 * everything else is refused once the signal is terminal.
 */
export function canApplyUpdate(status: SignalStatus, type: SignalUpdateType): boolean {
  if (type === 'COMMENT') return true;
  if (isTerminal(status)) return false;
  if (status === 'DRAFT') return type === 'CANCELLED';
  return true;
}

/** The update actions an admin should be offered for the current status. */
export function availableUpdateActions(status: SignalStatus): SignalUpdateType[] {
  const all: SignalUpdateType[] = [
    'ENTRY_HIT',
    'MOVED_TO_BE',
    'TP1_HIT',
    'TP2_HIT',
    'TP3_HIT',
    'SL_HIT',
    'PARTIAL_CLOSE',
    'CLOSE_WIN',
    'CLOSE_LOSS',
    'CANCELLED',
    'COMMENT',
  ];
  return all.filter((t) => canApplyUpdate(status, t));
}
