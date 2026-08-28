import { useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { login, register } from '@/lib/api';
import { useSession } from '@/lib/session';
import { theme } from '@/lib/theme';
import { Button } from '@/components/ui';

export default function AuthScreen() {
  const { refresh } = useSession();
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      if (mode === 'login') await login(email.trim(), password);
      else await register({ email: email.trim(), password, displayName: displayName.trim() });
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong');
    } finally {
      setBusy(false);
    }
  }

  const canSubmit =
    email.includes('@') && password.length >= 8 && (mode === 'login' || displayName.length >= 2);

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <Text style={styles.brand}>Signals Academy</Text>
          <Text style={styles.tagline}>
            Live trade analysis and structured trading education.
          </Text>

          {error ? <Text style={styles.error}>{error}</Text> : null}

          {mode === 'register' && (
            <View style={styles.field}>
              <Text style={styles.label}>Name</Text>
              <TextInput
                style={styles.input}
                value={displayName}
                onChangeText={setDisplayName}
                placeholder="Your name"
                placeholderTextColor={theme.muted}
                autoCapitalize="words"
              />
            </View>
          )}

          <View style={styles.field}>
            <Text style={styles.label}>Email</Text>
            <TextInput
              style={styles.input}
              value={email}
              onChangeText={setEmail}
              placeholder="you@example.com"
              placeholderTextColor={theme.muted}
              autoCapitalize="none"
              autoComplete="email"
              keyboardType="email-address"
            />
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Password</Text>
            <TextInput
              style={styles.input}
              value={password}
              onChangeText={setPassword}
              placeholder="At least 8 characters"
              placeholderTextColor={theme.muted}
              secureTextEntry
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            />
          </View>

          <Button
            label={mode === 'login' ? 'Sign in' : 'Create account'}
            onPress={submit}
            disabled={!canSubmit}
            loading={busy}
          />

          <View style={{ height: 10 }} />

          <Button
            label={mode === 'login' ? 'I need an account' : 'I already have an account'}
            variant="ghost"
            onPress={() => {
              setMode(mode === 'login' ? 'register' : 'login');
              setError(null);
            }}
          />

          <Text style={styles.legal}>
            Educational content only. Not financial advice. Trading carries a high risk of loss.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 24, paddingTop: 60, flexGrow: 1, justifyContent: 'center' },
  brand: { color: theme.text, fontSize: 28, fontWeight: '800', letterSpacing: -0.5 },
  tagline: { color: theme.muted, fontSize: 14, marginTop: 6, marginBottom: 28, lineHeight: 20 },
  field: { marginBottom: 14 },
  label: { color: theme.muted, fontSize: 12, marginBottom: 6, fontWeight: '600' },
  input: {
    backgroundColor: theme.surface,
    borderColor: theme.border,
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 13,
    color: theme.text,
    fontSize: 15,
  },
  error: {
    color: theme.sell,
    backgroundColor: `${theme.sell}18`,
    borderRadius: 8,
    padding: 10,
    marginBottom: 14,
    fontSize: 13,
  },
  legal: { color: theme.muted, fontSize: 11, lineHeight: 16, marginTop: 28, textAlign: 'center' },
});
