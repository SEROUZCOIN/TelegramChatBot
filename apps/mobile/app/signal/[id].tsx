import { useQuery } from '@tanstack/react-query';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { STATUS_LABEL, UPDATE_LABEL, type SignalStatus, type SignalUpdateType } from '@tsp/shared';
import { api } from '@/lib/api';
import { statusColor, theme } from '@/lib/theme';
import { AdBanner } from '@/components/ad-banner';
import {
  Badge,
  Button,
  Card,
  ChartImage,
  ErrorState,
  Loading,
  RiskFooter,
} from '@/components/ui';

interface SignalDetail {
  id: string;
  symbol: string;
  direction: 'BUY' | 'SELL';
  timeframe: string;
  status: SignalStatus;
  minPlan: string;
  locked: boolean;
  entryLow?: number;
  entryHigh?: number;
  sl?: number;
  tp1?: number | null;
  tp2?: number | null;
  tp3?: number | null;
  beTrigger?: number | null;
  analysisText?: string;
  resultPips?: number | null;
  metrics?: {
    slPips: number;
    maxRR: number | null;
    targets: Array<{ level: number; price: number; pips: number; rr: number | null }>;
  };
  images?: Array<{ id: string; url: string }>;
  updates?: Array<{
    id: string;
    type: SignalUpdateType;
    note: string;
    price: number | null;
    resultPips: number | null;
    createdAt: string;
  }>;
}

export default function SignalDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();

  const { data, isLoading, error } = useQuery({
    queryKey: ['signal', id],
    queryFn: () => api<SignalDetail>(`/signals/${id}`),
    enabled: Boolean(id),
    refetchInterval: 30_000,
  });

  if (isLoading) return <Loading />;
  if (error) return <ErrorState message={(error as Error).message} />;
  if (!data) return null;

  const dirColor = data.direction === 'BUY' ? theme.buy : theme.sell;

  /**
   * A locked signal never carried its levels over the wire, so there is nothing
   * to hide here — the screen simply has nothing to show and makes the case for
   * upgrading instead.
   */
  if (data.locked) {
    return (
      <View style={styles.screen}>
        <ScrollView contentContainerStyle={styles.scroll}>
          <Card>
            <View style={styles.header}>
              <Text style={styles.symbol}>{data.symbol}</Text>
              <Badge label={data.direction} color={dirColor} />
              <Badge label={STATUS_LABEL[data.status]} color={statusColor(data.status)} />
            </View>
            <Text style={styles.lockedTitle}>This signal is part of the {data.minPlan} plan</Text>
            <Text style={styles.lockedBody}>
              Subscribers see the entry zone, all take-profit targets, the stop loss, the
              break-even trigger, the chart, and every update as the trade develops.
            </Text>
            <View style={{ height: 14 }} />
            <Button label="See plans" onPress={() => router.push('/plans')} />
          </Card>
        </ScrollView>
        <RiskFooter />
      </View>
    );
  }

  return (
    <View style={styles.screen}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <View style={styles.header}>
          <Text style={styles.symbol}>{data.symbol}</Text>
          <Badge label={data.direction} color={dirColor} />
          <Badge label={data.timeframe} />
          <Badge label={STATUS_LABEL[data.status]} color={statusColor(data.status)} />
        </View>

        {data.images?.[0] && (
          <View style={{ marginBottom: 14 }}>
            <ChartImage uri={data.images[0].url} />
          </View>
        )}

        <Card style={{ marginBottom: 14 }}>
          <Text style={styles.cardTitle}>Levels</Text>

          <Row
            label="Entry"
            value={
              data.entryHigh && data.entryHigh !== data.entryLow
                ? `${data.entryLow} – ${data.entryHigh}`
                : String(data.entryLow)
            }
          />
          <Row
            label="Stop loss"
            value={`${data.sl}`}
            note={`${data.metrics?.slPips ?? '—'} pips`}
            color={theme.sell}
          />

          {data.metrics?.targets.map((t) => (
            <Row
              key={t.level}
              label={`Take profit ${t.level}`}
              value={String(t.price)}
              note={`${t.pips} pips${t.rr ? ` · ${t.rr}R` : ''}`}
              color={theme.buy}
            />
          ))}

          {data.beTrigger != null && (
            <Row label="Move to break-even at" value={String(data.beTrigger)} color={theme.warn} />
          )}

          {data.resultPips != null && (
            <Row
              label="Result"
              value={`${data.resultPips > 0 ? '+' : ''}${data.resultPips} pips`}
              color={data.resultPips >= 0 ? theme.buy : theme.sell}
            />
          )}
        </Card>

        {data.analysisText ? (
          <Card style={{ marginBottom: 14 }}>
            <Text style={styles.cardTitle}>Analysis</Text>
            <Text style={styles.analysis}>{data.analysisText}</Text>
          </Card>
        ) : null}

        {/* The live thread. This is what a subscriber is really paying for —
            not the call alone, but knowing what happened to it. */}
        <Card>
          <Text style={styles.cardTitle}>Timeline</Text>
          {!data.updates?.length ? (
            <Text style={styles.muted}>No updates yet. You will be notified as this moves.</Text>
          ) : (
            data.updates.map((u, i) => (
              <View key={u.id} style={styles.timelineRow}>
                <View style={styles.timelineMarker}>
                  <View
                    style={[
                      styles.dot,
                      { backgroundColor: markerColor(u.type) },
                      i === 0 && { width: 11, height: 11 },
                    ]}
                  />
                  {i < (data.updates?.length ?? 0) - 1 && <View style={styles.line} />}
                </View>
                <View style={styles.timelineBody}>
                  <Text style={styles.timelineTitle}>{UPDATE_LABEL[u.type]}</Text>
                  {u.price != null && <Text style={styles.muted}>at {u.price}</Text>}
                  {u.note ? <Text style={styles.muted}>{u.note}</Text> : null}
                  <Text style={styles.timestamp}>
                    {new Date(u.createdAt).toLocaleString('en-GB', {
                      day: '2-digit',
                      month: 'short',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </Text>
                </View>
              </View>
            ))
          )}
        </Card>
      </ScrollView>
      <AdBanner slot="SIGNAL_DETAIL" />
      <RiskFooter />
    </View>
  );
}

function Row({
  label,
  value,
  note,
  color,
}: {
  label: string;
  value: string;
  note?: string;
  color?: string;
}) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <View style={{ alignItems: 'flex-end' }}>
        <Text style={[styles.rowValue, color ? { color } : null]}>{value}</Text>
        {note ? <Text style={styles.rowNote}>{note}</Text> : null}
      </View>
    </View>
  );
}

function markerColor(type: SignalUpdateType): string {
  if (type === 'SL_HIT' || type === 'CLOSE_LOSS') return theme.sell;
  if (type.startsWith('TP') || type === 'CLOSE_WIN') return theme.buy;
  if (type === 'MOVED_TO_BE') return theme.warn;
  return theme.accent;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 14, paddingBottom: 24 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 14, flexWrap: 'wrap' },
  symbol: { color: theme.text, fontSize: 22, fontWeight: '800' },
  cardTitle: {
    color: theme.muted,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginBottom: 10,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.border,
  },
  rowLabel: { color: theme.muted, fontSize: 13 },
  rowValue: { color: theme.text, fontSize: 15, fontWeight: '700' },
  rowNote: { color: theme.muted, fontSize: 11, marginTop: 1 },
  analysis: { color: theme.text, fontSize: 14, lineHeight: 21 },
  muted: { color: theme.muted, fontSize: 13, lineHeight: 19 },
  lockedTitle: { color: theme.text, fontSize: 16, fontWeight: '700', marginTop: 12 },
  lockedBody: { color: theme.muted, fontSize: 14, lineHeight: 21, marginTop: 6 },
  timelineRow: { flexDirection: 'row', gap: 12 },
  timelineMarker: { alignItems: 'center', width: 14, paddingTop: 5 },
  dot: { width: 8, height: 8, borderRadius: 6 },
  line: { flex: 1, width: 1.5, backgroundColor: theme.border, marginTop: 3 },
  timelineBody: { flex: 1, paddingBottom: 16 },
  timelineTitle: { color: theme.text, fontSize: 14, fontWeight: '700' },
  timestamp: { color: theme.muted, fontSize: 11, marginTop: 3 },
});
