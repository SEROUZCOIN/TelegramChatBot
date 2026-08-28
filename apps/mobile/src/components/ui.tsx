import { Image } from 'expo-image';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { theme } from '../lib/theme';

export function Screen({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[styles.screen, style]}>{children}</View>;
}

export function Card({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function Title({ children }: { children: React.ReactNode }) {
  return <Text style={styles.title}>{children}</Text>;
}

export function Body({ children, muted }: { children: React.ReactNode; muted?: boolean }) {
  return <Text style={[styles.body, muted && { color: theme.muted }]}>{children}</Text>;
}

export function Badge({ label, color }: { label: string; color?: string }) {
  return (
    <View style={[styles.badge, color ? { borderColor: color } : null]}>
      <Text style={[styles.badgeText, color ? { color } : null]}>{label}</Text>
    </View>
  );
}

export function Button({
  label,
  onPress,
  variant = 'primary',
  disabled,
  loading,
}: {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'ghost' | 'danger';
  disabled?: boolean;
  loading?: boolean;
}) {
  const bg =
    variant === 'primary' ? theme.accent : variant === 'danger' ? theme.sell : theme.surface2;

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={disabled || loading}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: bg, opacity: disabled || loading ? 0.5 : pressed ? 0.85 : 1 },
        variant === 'ghost' && { borderWidth: 1, borderColor: theme.border },
      ]}
    >
      {loading ? (
        <ActivityIndicator color="#fff" />
      ) : (
        <Text style={styles.buttonText}>{label}</Text>
      )}
    </Pressable>
  );
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <View style={styles.centered}>
      <ActivityIndicator color={theme.accent} />
      <Text style={[styles.body, { color: theme.muted, marginTop: 10 }]}>{label}</Text>
    </View>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <View style={styles.centered}>
      <Text style={[styles.body, { color: theme.sell, textAlign: 'center' }]}>{message}</Text>
    </View>
  );
}

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <View style={styles.centered}>
      <Text style={styles.emptyTitle}>{title}</Text>
      {hint ? <Text style={[styles.body, { color: theme.muted, textAlign: 'center' }]}>{hint}</Text> : null}
    </View>
  );
}

/**
 * The disclaimer strip that sits on every signal surface.
 *
 * Repeated rather than shown once at onboarding, because it has to be visible
 * next to the thing it qualifies — a set of trade levels — not buried in a
 * settings page.
 */
export function RiskFooter() {
  return (
    <View style={styles.riskFooter}>
      <Text style={styles.riskText}>
        Educational analysis only. Not financial advice. Trading carries a high risk of loss and
        past performance does not indicate future results.
      </Text>
    </View>
  );
}

export function ChartImage({ uri }: { uri: string }) {
  return <Image source={{ uri }} style={styles.chart} contentFit="cover" transition={200} />;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  card: {
    backgroundColor: theme.surface,
    borderColor: theme.border,
    borderWidth: 1,
    borderRadius: theme.radius,
    padding: 16,
  },
  title: { color: theme.text, fontSize: 22, fontWeight: '700', letterSpacing: -0.3 },
  body: { color: theme.text, fontSize: 14, lineHeight: 21 },
  badge: {
    borderWidth: 1,
    borderColor: theme.border,
    backgroundColor: theme.surface2,
    borderRadius: 999,
    paddingHorizontal: 9,
    paddingVertical: 3,
    alignSelf: 'flex-start',
  },
  badgeText: { color: theme.muted, fontSize: 11, fontWeight: '700' },
  button: {
    borderRadius: 10,
    paddingVertical: 13,
    paddingHorizontal: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: { color: '#fff', fontSize: 15, fontWeight: '700' },
  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32 },
  emptyTitle: { color: theme.text, fontSize: 16, fontWeight: '600', marginBottom: 6 },
  riskFooter: {
    borderTopWidth: 1,
    borderTopColor: theme.border,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  riskText: { color: theme.muted, fontSize: 11, lineHeight: 16 },
  chart: { width: '100%', aspectRatio: 16 / 10, borderRadius: 10, backgroundColor: theme.surface2 },
});
