import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { useAdConfig, useTrackingPermission } from '@/lib/ads';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { AdBanner } from '@/components/ad-banner';
import { SignalCard, type FeedSignal } from '@/components/signal-card';
import { Badge, EmptyState, ErrorState, Loading, RiskFooter } from '@/components/ui';

interface Feed {
  items: FeedSignal[];
  nextCursor: string | null;
  viewerPlan: string;
}

interface Stats {
  winRate: number | null;
  totalPips: number;
  wins: number;
  losses: number;
  breakEven: number;
  open: number;
}

export default function SignalsTab() {
  const router = useRouter();
  const { entitlements } = useSession();
  const { data: ads } = useAdConfig();
  const [openOnly, setOpenOnly] = useState(false);

  // Only ask for tracking consent from users who will actually see ads.
  useTrackingPermission(Boolean(ads?.showAds));

  const stats = useQuery({
    queryKey: ['stats'],
    queryFn: () => api<Stats>('/signals/stats?days=90'),
  });

  const feed = useInfiniteQuery({
    queryKey: ['feed', openOnly],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      api<Feed>(
        `/signals?limit=20${openOnly ? '&openOnly=true' : ''}${pageParam ? `&cursor=${pageParam}` : ''}`,
      ),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });

  if (feed.isLoading) return <Loading />;
  if (feed.isError) return <ErrorState message={(feed.error as Error).message} />;

  const items = feed.data?.pages.flatMap((p) => p.items) ?? [];
  const s = stats.data;

  return (
    <View style={styles.container}>
      <FlatList
        data={items}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl
            refreshing={feed.isRefetching}
            onRefresh={() => void feed.refetch()}
            tintColor={theme.accent}
          />
        }
        onEndReached={() => feed.hasNextPage && void feed.fetchNextPage()}
        onEndReachedThreshold={0.4}
        ListHeaderComponent={
          <View>
            {/* The public record. Shown to everyone, including free users,
                because it is the reason to subscribe — and it is computed from
                the ledger, so it is the same number a subscriber could total
                by hand from this very feed. */}
            {s && (
              <View style={styles.statsRow}>
                <Stat label="Win rate" value={s.winRate === null ? '—' : `${s.winRate}%`} />
                <Stat
                  label="Net pips (90d)"
                  value={`${s.totalPips > 0 ? '+' : ''}${s.totalPips}`}
                  color={s.totalPips >= 0 ? theme.buy : theme.sell}
                />
                <Stat label="Open" value={String(s.open)} />
                <Stat label="Record" value={`${s.wins}W ${s.losses}L ${s.breakEven}BE`} small />
              </View>
            )}

            <View style={styles.filters}>
              <Pressable
                onPress={() => setOpenOnly(false)}
                style={[styles.chip, !openOnly && styles.chipActive]}
              >
                <Text style={[styles.chipText, !openOnly && styles.chipTextActive]}>All</Text>
              </Pressable>
              <Pressable
                onPress={() => setOpenOnly(true)}
                style={[styles.chip, openOnly && styles.chipActive]}
              >
                <Text style={[styles.chipText, openOnly && styles.chipTextActive]}>Open only</Text>
              </Pressable>
              <View style={{ flex: 1 }} />
              <Badge label={entitlements?.plan ?? 'FREE'} color={theme.accent} />
            </View>

            {entitlements && !entitlements.canViewSignals && (
              <Pressable onPress={() => router.push('/plans')} style={styles.upsell}>
                <Text style={styles.upsellTitle}>You are on the free tier</Text>
                <Text style={styles.upsellBody}>
                  Signal levels — entry, targets and stop — are part of the Signals plan. Tap to see
                  what each plan includes.
                </Text>
              </Pressable>
            )}
          </View>
        }
        renderItem={({ item }) => <SignalCard signal={item} />}
        ListEmptyComponent={
          <EmptyState title="No signals yet" hint="New setups appear here as they are published." />
        }
      />
      {/* Renders nothing when the server sent no unit id for this viewer. */}
      <AdBanner slot="FEED_INLINE" />
      <RiskFooter />
    </View>
  );
}

function Stat({
  label,
  value,
  color,
  small,
}: {
  label: string;
  value: string;
  color?: string;
  small?: boolean;
}) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, small && { fontSize: 13 }, color ? { color } : null]}>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.bg },
  list: { padding: 14, paddingBottom: 24 },
  statsRow: {
    flexDirection: 'row',
    backgroundColor: theme.surface,
    borderColor: theme.border,
    borderWidth: 1,
    borderRadius: theme.radius,
    padding: 14,
    marginBottom: 12,
    gap: 8,
  },
  stat: { flex: 1 },
  statLabel: { color: theme.muted, fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.4 },
  statValue: { color: theme.text, fontSize: 17, fontWeight: '700', marginTop: 3 },
  filters: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 },
  chip: {
    borderWidth: 1,
    borderColor: theme.border,
    backgroundColor: theme.surface,
    borderRadius: 999,
    paddingHorizontal: 13,
    paddingVertical: 6,
  },
  chipActive: { backgroundColor: theme.accent, borderColor: theme.accent },
  chipText: { color: theme.muted, fontSize: 12, fontWeight: '600' },
  chipTextActive: { color: '#fff' },
  upsell: {
    backgroundColor: `${theme.accent}18`,
    borderColor: theme.accent,
    borderWidth: 1,
    borderRadius: theme.radius,
    padding: 14,
    marginBottom: 12,
  },
  upsellTitle: { color: theme.text, fontSize: 14, fontWeight: '700' },
  upsellBody: { color: theme.muted, fontSize: 13, lineHeight: 19, marginTop: 4 },
});
