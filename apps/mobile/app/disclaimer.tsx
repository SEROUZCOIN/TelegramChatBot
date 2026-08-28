import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { api } from '@/lib/api';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { Button, Loading } from '@/components/ui';

/**
 * The risk disclosure gate.
 *
 * Text and version come from the API rather than the bundle, so the wording can
 * be corrected without a release through two store review queues. Acceptance is
 * recorded server-side with the version, which is what makes it an auditable
 * record rather than a checkbox.
 */
export default function DisclaimerScreen() {
  const { refresh, signOut } = useSession();
  const [busy, setBusy] = useState(false);
  const [scrolledToEnd, setScrolledToEnd] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['disclaimer'],
    queryFn: () => api<{ version: string; text: string }>('/auth/disclaimer', { auth: false }),
  });

  async function accept() {
    if (!data) return;
    setBusy(true);
    setError(null);
    try {
      await api('/auth/disclaimer/accept', {
        method: 'POST',
        body: JSON.stringify({ version: data.version }),
      });
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not record your acceptance');
    } finally {
      setBusy(false);
    }
  }

  if (isLoading || !data) return <Loading label="Loading risk disclosure…" />;

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.title}>Before you continue</Text>
        <Text style={styles.version}>Version {data.version}</Text>
      </View>

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={{ padding: 20 }}
        onScroll={({ nativeEvent: e }) => {
          const atEnd =
            e.layoutMeasurement.height + e.contentOffset.y >= e.contentSize.height - 40;
          if (atEnd) setScrolledToEnd(true);
        }}
        scrollEventThrottle={64}
      >
        <Text style={styles.body}>{data.text}</Text>
      </ScrollView>

      <View style={styles.footer}>
        {error ? <Text style={styles.error}>{error}</Text> : null}
        {!scrolledToEnd && (
          <Text style={styles.hint}>Scroll to the end to continue.</Text>
        )}
        <Button
          label="I understand and accept"
          onPress={accept}
          disabled={!scrolledToEnd}
          loading={busy}
        />
        <View style={{ height: 8 }} />
        <Button label="Sign out" variant="ghost" onPress={() => void signOut()} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: theme.bg },
  header: { padding: 20, paddingBottom: 12 },
  title: { color: theme.text, fontSize: 24, fontWeight: '800' },
  version: { color: theme.muted, fontSize: 12, marginTop: 4 },
  scroll: { flex: 1, backgroundColor: theme.surface, marginHorizontal: 16, borderRadius: 12 },
  body: { color: theme.text, fontSize: 13, lineHeight: 21 },
  footer: { padding: 16, borderTopWidth: 1, borderTopColor: theme.border },
  hint: { color: theme.muted, fontSize: 12, textAlign: 'center', marginBottom: 8 },
  error: { color: theme.sell, fontSize: 13, marginBottom: 8, textAlign: 'center' },
});
