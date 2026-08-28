import { Tabs } from 'expo-router';
import { Text } from 'react-native';
import { theme } from '@/lib/theme';

const icon = (glyph: string) => {
  const TabIcon = ({ color }: { color: string }) => (
    <Text style={{ color, fontSize: 18 }}>{glyph}</Text>
  );
  TabIcon.displayName = `TabIcon(${glyph})`;
  return TabIcon;
};

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerStyle: { backgroundColor: theme.surface },
        headerTintColor: theme.text,
        headerTitleStyle: { fontWeight: '700' },
        tabBarStyle: { backgroundColor: theme.surface, borderTopColor: theme.border },
        tabBarActiveTintColor: theme.accent,
        tabBarInactiveTintColor: theme.muted,
        sceneStyle: { backgroundColor: theme.bg },
      }}
    >
      <Tabs.Screen name="index" options={{ title: 'Signals', tabBarIcon: icon('◈') }} />
      <Tabs.Screen name="academy" options={{ title: 'Academy', tabBarIcon: icon('▤') }} />
      <Tabs.Screen name="live" options={{ title: 'Live', tabBarIcon: icon('◉') }} />
      <Tabs.Screen name="plans" options={{ title: 'Plans', tabBarIcon: icon('◆') }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile', tabBarIcon: icon('◐') }} />
    </Tabs>
  );
}
