import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import * as WebBrowser from 'expo-web-browser';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { Badge, Button, Card, Loading } from '@/components/ui';

interface AppLink {
  id: string;
  label: string;
  url: string;
  icon: string;
  category: string;
}

export default function ProfileTab() {
  const qc = useQueryClient();
  const { profile, entitlements, signOut, refresh } = useSession();

  const links = useQuery({
    queryKey: ['links'],
    queryFn: () => api<AppLink[]>('/links', { auth: false }),
  });

  /**
   * Taps are registered with the API, which returns the destination.
   *
   * Routing the tap through the server means the links panel shows real open
   * counts, and a link's destination can be changed later without shipping a
   * new build through store review.
   */
  const openLink = useMutation({
    mutationFn: (id: string) => api<{ url: string | null }>(`/links/${id}/click`, { method: 'POST' }),
    onSuccess: async (r, id) => {
      const fallback = links.data?.find((l) => l.id === id)?.url;
      const target = r.url ?? fallback;
      if (!target) return;

      // Telegram and other app links need the OS handler, not an in-app browser.
      if (/^(tg|https:\/\/t\.me)/.test(target)) {
        const opened = await Linking.canOpenURL(target);
        if (opened) return Linking.openURL(target);
      }
      await WebBrowser.openBrowserAsync(target);
    },
  });

  const linkCode = useMutation({
    mutationFn: () => api<{ code: string }>('/me/telegram/link-code', { method: 'POST' }),
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['me'] });
      Alert.alert(
        'Connect Telegram',
        `Open the bot and send:\n\n/start ${r.code}\n\nThe code works once and then expires.`,
      );
    },
  });

  const deleteAccount = useMutation({
    mutationFn: () => api('/me', { method: 'DELETE' }),
    onSuccess: () => void signOut(),
  });

  if (!profile) return <Loading />;

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.scroll}>
      <Card style={{ marginBottom: 14 }}>
        <Text style={styles.name}>{profile.displayName}</Text>
        <Text style={styles.email}>{profile.email}</Text>

        <View style={styles.planRow}>
          <Badge label={entitlements?.plan ?? 'FREE'} color={theme.accent} />
          <Text style={styles.planNote}>
            {entitlements?.expiresAt
              ? `Renews ${new Date(entitlements.expiresAt).toLocaleDateString('en-GB')}`
              : entitlements?.plan === 'FREE'
                ? 'No active subscription'
                : 'Lifetime access'}
          </Text>
        </View>
      </Card>

      <Card style={{ marginBottom: 14 }}>
        <Text style={styles.sectionTitle}>Telegram</Text>
        {profile.telegramUsername ? (
          <Text style={styles.body}>
            Connected as @{profile.telegramUsername}. Signals are delivered to your Telegram as well
            as here.
          </Text>
        ) : (
          <>
            <Text style={styles.body}>
              Connect your Telegram to receive signals there too, gated by your plan.
            </Text>
            <View style={{ height: 12 }} />
            <Button
              label="Connect Telegram"
              variant="ghost"
              onPress={() => linkCode.mutate()}
              loading={linkCode.isPending}
            />
          </>
        )}
      </Card>

      <Card style={{ marginBottom: 14 }}>
        <Text style={styles.sectionTitle}>Links</Text>
        {links.isLoading ? (
          <Text style={styles.body}>Loading…</Text>
        ) : !links.data?.length ? (
          <Text style={styles.body}>No links yet.</Text>
        ) : (
          links.data.map((link) => (
            <Pressable
              key={link.id}
              onPress={() => openLink.mutate(link.id)}
              style={({ pressed }) => [styles.link, pressed && { opacity: 0.75 }]}
            >
              <View style={{ flex: 1 }}>
                <Text style={styles.linkLabel}>{link.label}</Text>
                <Text style={styles.linkCategory}>{link.category.toLowerCase()}</Text>
              </View>
              <Text style={styles.chevron}>›</Text>
            </Pressable>
          ))
        )}
      </Card>

      <Card style={{ marginBottom: 14 }}>
        <Text style={styles.sectionTitle}>Legal</Text>
        <Text style={styles.body}>
          You accepted the risk disclosure (version {profile.riskDisclaimerVersion ?? '—'}) on{' '}
          {profile.riskDisclaimerAcceptedAt
            ? new Date(profile.riskDisclaimerAcceptedAt).toLocaleDateString('en-GB')
            : '—'}
          .
        </Text>
      </Card>

      <Button label="Sign out" variant="ghost" onPress={() => void signOut()} />

      <View style={{ height: 10 }} />

      {/* Required by Apple guideline 5.1.1(v) for any app with account
          creation. Its absence is a routine rejection. */}
      <Button
        label="Delete my account"
        variant="danger"
        loading={deleteAccount.isPending}
        onPress={() =>
          Alert.alert(
            'Delete your account?',
            'Your profile and personal data are removed and any active subscription is ' +
              'cancelled. This cannot be undone.',
            [
              { text: 'Keep my account', style: 'cancel' },
              {
                text: 'Delete',
                style: 'destructive',
                onPress: () => deleteAccount.mutate(),
              },
            ],
          )
        }
      />

      <Text style={styles.footnote}>
        Educational content only. Not financial advice. We are not a broker and never execute
        trades or hold funds.
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 14, paddingBottom: 28 },
  name: { color: theme.text, fontSize: 20, fontWeight: '800' },
  email: { color: theme.muted, fontSize: 13, marginTop: 2 },
  planRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 12 },
  planNote: { color: theme.muted, fontSize: 12 },
  sectionTitle: {
    color: theme.muted,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginBottom: 10,
  },
  body: { color: theme.text, fontSize: 13, lineHeight: 20 },
  link: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 11,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: theme.border,
  },
  linkLabel: { color: theme.text, fontSize: 14, fontWeight: '600' },
  linkCategory: { color: theme.muted, fontSize: 11, marginTop: 1 },
  chevron: { color: theme.muted, fontSize: 22 },
  footnote: { color: theme.muted, fontSize: 11, lineHeight: 17, marginTop: 20, textAlign: 'center' },
});
