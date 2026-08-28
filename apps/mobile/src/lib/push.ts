import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { useEffect } from 'react';
import { Platform } from 'react-native';
import { api } from './api';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

/**
 * Registers this device for signal alerts.
 *
 * Registration is idempotent and keyed on the push token rather than the user,
 * so a device that changes hands is reassigned instead of delivering one
 * person's paid signals to another.
 */
export async function registerForPush(): Promise<string | null> {
  if (!Device.isDevice) return null; // simulators cannot receive push

  const existing = await Notifications.getPermissionsAsync();
  let status = existing.status;

  if (status !== 'granted') {
    // Only asked once; a user who declines still gets the full in-app feed.
    ({ status } = await Notifications.requestPermissionsAsync());
  }
  if (status !== 'granted') return null;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('signals', {
      name: 'Trade signals',
      importance: Notifications.AndroidImportance.HIGH,
      vibrationPattern: [0, 250, 250, 250],
      lightColor: '#3b82f6',
    });
  }

  try {
    const token = (await Notifications.getExpoPushTokenAsync()).data;
    await api('/devices', {
      method: 'POST',
      body: JSON.stringify({
        pushToken: token,
        platform: Platform.OS === 'ios' ? 'ios' : 'android',
        appVersion: '1.0.0',
      }),
    });
    return token;
  } catch {
    // Push is a convenience; failing to register must never block the app.
    return null;
  }
}

/** Registers once the user is signed in, and routes taps to the right screen. */
export function usePushRegistration(enabled: boolean, onDeepLink: (path: string) => void): void {
  useEffect(() => {
    if (!enabled) return;
    void registerForPush();
  }, [enabled]);

  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      const link = response.notification.request.content.data?.deepLink;
      if (typeof link === 'string' && link.startsWith('/')) onDeepLink(link);
    });
    return () => sub.remove();
  }, [onDeepLink]);
}
