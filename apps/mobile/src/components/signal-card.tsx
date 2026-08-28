import { Link } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { STATUS_LABEL, type SignalStatus } from '@tsp/shared';
import { statusColor, theme } from '../lib/theme';
import { Badge } from './ui';

export interface FeedSignal {
  id: string;
  symbol: string;
  direction: 'BUY' | 'SELL';
  timeframe: string;
  status: SignalStatus;
  minPlan: string;
  publishedAt: string | null;
  locked: boolean;
  updateCount?: number;
  entryLow?: number;
  entryHigh?: number;
  sl?: number;
  resultPips?: number | null;
  metrics?: { slPips: number; maxRR: number | null; targets: Array<{ level: number; pips: number }> };
}

/**
 * A signal in the feed.
 *
 * A locked card is not a blurred version of an unlocked one — the levels are
 * not in the payload at all. So it shows what it genuinely knows (the pair, the
 * direction, that a call was made and when) and makes the upgrade the point.
 * That preview is the entire sales argument: it proves the call was timely
 * without giving away what subscribers pay for.
 */
export function SignalCard({ signal }: { signal: FeedSignal }) {
  const dirColor = signal.direction === 'BUY' ? theme.buy : theme.sell;

  return (
    <Link href={`/signal/${signal.id}`} asChild>
      <Pressable style={({ pressed }) => [styles.card, pressed && { opacity: 0.85 }]}>
        <View style={styles.header}>
          <View style={styles.headerLeft}>
            <Text style={styles.symbol}>{signal.symbol}</Text>
            <View style={[styles.dirPill, { backgroundColor: `${dirColor}22`, borderColor: dirColor }]}>
              <Text style={[styles.dirText, { color: dirColor }]}>{signal.direction}</Text>
            </View>
            <Text style={styles.timeframe}>{signal.timeframe}</Text>
          </View>
          <Badge label={STATUS_LABEL[signal.status]} color={statusColor(signal.status)} />
        </View>

        {signal.locked ? (
          <View style={styles.lockedBody}>
            <Text style={styles.lockedTitle}>Entry, targets and stop are for subscribers</Text>
            <Text style={styles.lockedHint}>
              {signal.updateCount
                ? `${signal.updateCount} update${signal.updateCount === 1 ? '' : 's'} posted on this trade`
                : 'Tap to see what this plan includes'}
            </Text>
          </View>
        ) : (
          <View style={styles.levels}>
            <Level label="Entry" value={formatZone(signal.entryLow, signal.entryHigh)} />
            <Level
              label="Stop"
              value={`${signal.metrics?.slPips ?? '—'}p`}
              color={theme.sell}
            />
            <Level
              label="Targets"
              value={signal.metrics?.targets.map((t) => `${t.pips}p`).join(' · ') || '—'}
              color={theme.buy}
            />
            {signal.resultPips != null && (
              <Level
                label="Result"
                value={`${signal.resultPips > 0 ? '+' : ''}${signal.resultPips}p`}
                color={signal.resultPips >= 0 ? theme.buy : theme.sell}
              />
            )}
          </View>
        )}
      </Pressable>
    </Link>
  );
}

function Level({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <View style={styles.level}>
      <Text style={styles.levelLabel}>{label}</Text>
      <Text style={[styles.levelValue, color ? { color } : null]}>{value}</Text>
    </View>
  );
}

function formatZone(low?: number, high?: number): string {
  if (low == null) return '—';
  if (high == null || high === low) return String(low);
  return `${low}–${high}`;
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: theme.surface,
    borderColor: theme.border,
    borderWidth: 1,
    borderRadius: theme.radius,
    padding: 14,
    marginBottom: 10,
  },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  headerLeft: { flexDirection: 'row', alignItems: 'center', gap: 8, flexShrink: 1 },
  symbol: { color: theme.text, fontSize: 16, fontWeight: '700' },
  dirPill: { borderWidth: 1, borderRadius: 6, paddingHorizontal: 6, paddingVertical: 1 },
  dirText: { fontSize: 11, fontWeight: '800' },
  timeframe: { color: theme.muted, fontSize: 12 },
  lockedBody: {
    marginTop: 12,
    paddingVertical: 14,
    paddingHorizontal: 12,
    borderRadius: 10,
    backgroundColor: theme.surface2,
    borderWidth: 1,
    borderColor: theme.border,
    borderStyle: 'dashed',
  },
  lockedTitle: { color: theme.text, fontSize: 13, fontWeight: '600' },
  lockedHint: { color: theme.muted, fontSize: 12, marginTop: 3 },
  levels: { flexDirection: 'row', marginTop: 12, gap: 18, flexWrap: 'wrap' },
  level: { minWidth: 64 },
  levelLabel: { color: theme.muted, fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.5 },
  levelValue: { color: theme.text, fontSize: 14, fontWeight: '600', marginTop: 2 },
});
