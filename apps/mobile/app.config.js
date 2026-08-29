/**
 * Expo app configuration.
 *
 * This replaced the static app.json so the identity fields can come from the
 * environment. Three of them are effectively permanent once you publish —
 * the iOS bundle identifier, the Android package name, and the EAS project id —
 * and two of those can never be changed again for a live app. Keeping them in
 * env means an EAS build profile sets them per environment, and a staging build
 * can install alongside production instead of overwriting it.
 *
 * Before your first real build:
 *
 *   1. cd apps/mobile && eas init          → fills EAS_PROJECT_ID
 *   2. set APP_BUNDLE_ID to your own reverse-domain, e.g. com.yourdomain.signals
 *
 * ./preflight.sh reports both as blockers until they are real.
 */

// A reverse-domain you control. The default is deliberately an obviously
// invalid placeholder: Apple and Google both reject com.example.*, and
// shipping a guessed domain would be worse than failing loudly.
const BUNDLE_ID = process.env.APP_BUNDLE_ID ?? 'com.example.signalsacademy';

const NAME = process.env.APP_NAME ?? 'Signals Academy';
const SLUG = process.env.APP_SLUG ?? 'signals-academy';
const SCHEME = process.env.APP_SCHEME ?? 'tsp';

module.exports = {
  expo: {
    name: NAME,
    slug: SLUG,
    version: '1.0.0',
    orientation: 'portrait',
    scheme: SCHEME,
    userInterfaceStyle: 'dark',
    splash: {
      resizeMode: 'contain',
      backgroundColor: '#0b1120',
    },
    assetBundlePatterns: ['**/*'],

    ios: {
      supportsTablet: true,
      bundleIdentifier: BUNDLE_ID,
      config: { usesNonExemptEncryption: false },
      infoPlist: {
        // Required before any tracking-based ad. Apple rejects an app that
        // ships an ads SDK without this string (guideline 5.1.2(i)).
        NSUserTrackingUsageDescription:
          'This identifier is used to show you more relevant ads. You can decline and still use every feature of the app.',
        ITSAppUsesNonExemptEncryption: false,
      },
    },

    android: {
      package: BUNDLE_ID,
      adaptiveIcon: { backgroundColor: '#0b1120' },
      permissions: [
        'android.permission.INTERNET',
        'com.google.android.gms.permission.AD_ID',
      ],
    },

    plugins: [
      'expo-router',
      'expo-secure-store',
      'expo-video',
      'expo-tracking-transparency',
      ['expo-notifications', { color: '#3b82f6' }],
    ],

    extra: {
      apiUrl: process.env.EXPO_PUBLIC_API_URL ?? 'http://localhost:3000/api',
      eas: {
        // Populated by `eas init`. The zero UUID fails every build immediately.
        projectId: process.env.EAS_PROJECT_ID ?? '00000000-0000-0000-0000-000000000000',
      },
    },
  },
};
