import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import * as WebBrowser from 'expo-web-browser';
import { useRouter } from 'expo-router';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { Badge, Button, Card, EmptyState, Loading } from '@/components/ui';

interface Session {
  id: string;
  status: string;
  scheduledAt: string;
  durationMin: number;
  topic: string;
  coach: { id: string; displayName: string } | null;
}

export default function LiveTab() {
  const router = useRouter();
  const qc = useQueryClient();
  const { entitlements } = useSession();

  const { data, isLoading } = useQuery({
    queryKey: ['coaching'],
    queryFn: () => api<Session[]>('/coaching/sessions'),
    enabled: Boolean(entitlements?.canBookCoaching),
  });

  const book = useMutation({
    mutationFn: () =>
      api('/coaching/sessions', {
        method: 'POST',
        body: JSON.stringify({
          // Default to a slot a week out; the coach confirms the exact time.
          scheduledAt: new Date(Date.now() + 7 * 86_400_000).toISOString(),
          durationMin: 60,
          topic: 'Introductory session',
        }),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['coaching'] });
      Alert.alert('Requested', 'Your coach will confirm the time shortly.');
    },
    onError: (err) =>
      Alert.alert('Could not book', err instanceof Error ? err.message : 'Try again.'),
  });

  const join = useMutation({
    mutationFn: (id: string) => api<{ roomUrl: string }>(`/coaching/sessions/${id}/join`, { method: 'POST' }),
    onSuccess: (r) => void WebBrowser.openBrowserAsync(r.roomUrl),
    onError: (err) =>
      Alert.alert('Could not join', err instanceof Error ? err.message : 'Try again.'),
  });

  /**
   * Coaching is one-to-one only. That is a product decision with a policy
   * reason behind it: Apple guideline 3.1.3(d) permits outside payment only
   * for real-time services between two individuals, so group sessions would
   * force these tiers onto in-app purchase.
   */
  if (!entitlements?.canBookCoaching) {
    return (
      <ScrollView style={styles.screen} contentContainerStyle={styles.scroll}>
        <Card>
          <Text style={styles.title}>Live one-to-one coaching</Text>
          <Text style={styles.body}>
            Pro and Ultra include private sessions with a coach — screen share, your charts, your
            trading plan reviewed directly. Sessions are always one-to-one, never a group call.
          </Text>
          <View style={{ height: 14 }} />
          <Button label="See plans" onPress={() => router.push('/plans')} />
        </Card>
      </ScrollView>
    );
  }

  if (isLoading) return <Loading />;
  const sessions = data ?? [];

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.scroll}>
      <View style={{ marginBottom: 14 }}>
        <Button label="Book a session" onPress={() => book.mutate()} loading={book.isPending} />
      </View>

      {sessions.length === 0 ? (
        <EmptyState title="No sessions booked" hint="Book your first session above." />
      ) : (
        sessions.map((s) => {
          const when = new Date(s.scheduledAt);
          const joinable = s.status === 'SCHEDULED' || s.status === 'LIVE';

          return (
            <Card key={s.id} style={{ marginBottom: 12 }}>
              <View style={styles.header}>
                <Text style={styles.when}>
                  {when.toLocaleString('en-GB', {
                    weekday: 'short',
                    day: '2-digit',
                    month: 'short',
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </Text>
                <Badge label={s.status} color={joinable ? theme.buy : theme.muted} />
              </View>
              <Text style={styles.body}>
                {s.durationMin} minutes
                {s.coach ? ` · with ${s.coach.displayName}` : ' · coach to be assigned'}
              </Text>
              {s.topic ? <Text style={styles.body}>{s.topic}</Text> : null}

              {joinable && (
                <>
                  <View style={{ height: 12 }} />
                  <Button
                    label="Join session"
                    onPress={() => join.mutate(s.id)}
                    loading={join.isPending}
                  />
                </>
              )}
            </Card>
          );
        })
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 14, paddingBottom: 24 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  title: { color: theme.text, fontSize: 18, fontWeight: '800', marginBottom: 8 },
  when: { color: theme.text, fontSize: 15, fontWeight: '700' },
  body: { color: theme.muted, fontSize: 13, lineHeight: 20, marginTop: 3 },
});
