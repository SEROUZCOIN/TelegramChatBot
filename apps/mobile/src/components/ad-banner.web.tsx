/**
 * Web has no AdMob implementation — the SDK is native-only, and Metro resolves
 * this file instead of `ad-banner.tsx` for the web target.
 *
 * Returning null keeps the web preview buildable without weakening the real
 * guarantee: on iOS and Android the native banner still renders only when the
 * server sent a unit id for that viewer.
 */
export function AdBanner(_props: { slot: string }) {
  return null;
}
