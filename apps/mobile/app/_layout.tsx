import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { SessionProvider, useSession } from '@/lib/session';
import { usePushRegistration } from '@/lib/push';
import { theme } from '@/lib/theme';
import { Loading } from '@/components/ui';
import DisclaimerScreen from './disclaimer';
import AuthScreen from './auth';

export default function RootLayout() {
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { retry: 1 } } }));

  return (
    <SafeAreaProvider>
      <QueryClientProvider client={client}>
        <SessionProvider>
          <StatusBar style="light" />
          <Gate />
        </SessionProvider>
      </QueryClientProvider>
    </SafeAreaProvider>
  );
}

/**
 * Nothing renders until the user is signed in *and* has accepted the current
 * risk disclaimer. The disclaimer is not skippable and not a banner — it is the
 * compliance artifact that lets a trading app pass review, so it sits in front
 * of the router rather than inside it.
 */
function Gate() {
  const { status } = useSession();
  const router = useRouter();

  // Registered only once the user is through the disclaimer, so the OS
  // permission prompt does not compete with the risk disclosure for attention.
  usePushRegistration(status === 'ready', (path) => router.push(path as never));

  if (status === 'loading') return <Loading label="Starting up…" />;
  if (status === 'anon') return <AuthScreen />;
  if (status === 'needs-disclaimer') return <DisclaimerScreen />;

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: theme.surface },
        headerTintColor: theme.text,
        headerTitleStyle: { fontWeight: '700' },
        contentStyle: { backgroundColor: theme.bg },
      }}
    >
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="signal/[id]" options={{ title: 'Signal' }} />
      <Stack.Screen name="lesson/[id]" options={{ title: 'Lesson' }} />
      <Stack.Screen name="disclaimer" options={{ title: 'Risk disclosure' }} />
      <Stack.Screen name="auth" options={{ headerShown: false }} />
    </Stack>
  );
}
