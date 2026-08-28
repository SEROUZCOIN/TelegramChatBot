import { useMutation, useQuery } from '@tanstack/react-query';
import * as WebBrowser from 'expo-web-browser';
import { useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { Badge, Button, Card, ErrorState, Loading, RiskFooter } from '@/components/ui';

interface Plan {
  code: string;
  name: string;
  tagline: string;
  priceCents: number;
  currency: string;
  interval: string;
  features: string[];
  providers: string[];
}

interface Checkout {
  url: string | null;
  paymentId: string;
  provider: string;
  instructions?: string;
  requiresManualReview?: boolean;
}

const PROVIDER_LABEL: Record<string, string> = {
  STRIPE: 'Pay by card',
  CRYPTO: 'Pay with crypto',
  BANK: 'Bank transfer',
  IAP: 'Buy in app',
};

export default function PlansTab() {
  const { entitlements } = useSession();
  const [pending, setPending] = useState<string | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['plans'],
    queryFn: () => api<Plan[]>('/plans', { auth: false }),
  });

  const checkout = useMutation({
    mutationFn: ({ planCode, provider }: { planCode: string; provider: string }) =>
      api<Checkout>('/payments/checkout', {
        method: 'POST',
        body: JSON.stringify({ planCode, provider }),
      }),
    onSuccess: async (session) => {
      setPending(null);

      if (session.url) {
        // Opened in the system browser rather than an embedded webview: a
        // webview wrapped around someone's card details is both a poor trust
        // signal and the pattern app review treats most harshly.
        await WebBrowser.openBrowserAsync(session.url);
        return;
      }

      Alert.alert(
        session.requiresManualReview ? 'Almost there' : 'Payment started',
        session.instructions ??
          'Follow the instructions sent to your email to complete this purchase.',
      );
    },
    onError: (err) => {
      setPending(null);
      Alert.alert('Could not start checkout', err instanceof Error ? err.message : 'Try again.');
    },
  });

  if (isLoading) return <Loading />;
  if (error) return <ErrorState message={(error as Error).message} />;

  return (
    <View style={styles.screen}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.heading}>Choose your plan</Text>
        <Text style={styles.sub}>
          You are currently on {entitlements?.plan ?? 'FREE'}.
        </Text>

        {(data ?? []).map((plan) => {
          const isCurrent = entitlements?.plan === plan.code;

          return (
            <Card key={plan.code} style={styles.plan}>
              <View style={styles.planHeader}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.planName}>{plan.name}</Text>
                  <Text style={styles.planTagline}>{plan.tagline}</Text>
                </View>
                {isCurrent && <Badge label="Current" color={theme.buy} />}
              </View>

              <View style={styles.priceRow}>
                <Text style={styles.price}>
                  {new Intl.NumberFormat('en-US', {
                    style: 'currency',
                    currency: plan.currency,
                    maximumFractionDigits: 0,
                  }).format(plan.priceCents / 100)}
                </Text>
                <Text style={styles.interval}>
                  {plan.interval === 'ONE_TIME' ? 'one-time' : `per ${plan.interval.toLowerCase()}`}
                </Text>
              </View>

              {plan.features.map((f) => (
                <View key={f} style={styles.featureRow}>
                  <Text style={styles.tick}>✓</Text>
                  <Text style={styles.feature}>{f}</Text>
                </View>
              ))}

              {!isCurrent && (
                <View style={styles.buttons}>
                  {plan.providers.length === 0 ? (
                    <Text style={styles.muted}>
                      Checkout for this plan is not available yet. Contact support to purchase.
                    </Text>
                  ) : (
                    plan.providers.map((provider) => (
                      <View key={provider} style={{ marginTop: 8 }}>
                        <Button
                          label={PROVIDER_LABEL[provider] ?? provider}
                          variant={provider === 'STRIPE' ? 'primary' : 'ghost'}
                          loading={pending === `${plan.code}:${provider}`}
                          onPress={() => {
                            setPending(`${plan.code}:${provider}`);
                            checkout.mutate({ planCode: plan.code, provider });
                          }}
                        />
                      </View>
                    ))
                  )}
                </View>
              )}
            </Card>
          );
        })}

        <Text style={styles.footnote}>
          Subscriptions renew until cancelled. One-time coaching packages do not expire. Prices are
          in USD.
        </Text>
      </ScrollView>
      <RiskFooter />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 14, paddingBottom: 28 },
  heading: { color: theme.text, fontSize: 24, fontWeight: '800' },
  sub: { color: theme.muted, fontSize: 13, marginTop: 4, marginBottom: 16 },
  plan: { marginBottom: 14 },
  planHeader: { flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  planName: { color: theme.text, fontSize: 18, fontWeight: '800' },
  planTagline: { color: theme.muted, fontSize: 13, marginTop: 2, lineHeight: 18 },
  priceRow: { flexDirection: 'row', alignItems: 'baseline', gap: 6, marginTop: 12, marginBottom: 12 },
  price: { color: theme.text, fontSize: 30, fontWeight: '800', letterSpacing: -0.5 },
  interval: { color: theme.muted, fontSize: 13 },
  featureRow: { flexDirection: 'row', gap: 8, marginBottom: 6 },
  tick: { color: theme.buy, fontSize: 13, fontWeight: '800' },
  feature: { color: theme.text, fontSize: 13, lineHeight: 19, flex: 1 },
  buttons: { marginTop: 10 },
  muted: { color: theme.muted, fontSize: 13, lineHeight: 19 },
  footnote: { color: theme.muted, fontSize: 11, lineHeight: 17, marginTop: 6, textAlign: 'center' },
});
