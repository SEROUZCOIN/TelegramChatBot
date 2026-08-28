import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useAdUnit } from '../lib/ads';
import { theme } from '../lib/theme';

/**
 * An AdMob banner for one slot.
 *
 * Renders nothing at all when the server did not send a unit id for this
 * viewer — which is how a Pro or Ultra subscriber is guaranteed an ad-free app
 * regardless of what the client build would otherwise do.
 *
 * The SDK is imported lazily so the app still runs in Expo Go, where the
 * native ads module is absent.
 */
export function AdBanner({ slot }: { slot: string }) {
  const unitId = useAdUnit(slot);
  const [Banner, setBanner] = useState<{
    BannerAd: React.ComponentType<{ unitId: string; size: string }>;
    size: string;
  } | null>(null);

  useEffect(() => {
    if (!unitId) return;
    let cancelled = false;

    void (async () => {
      try {
        const ads = await import('react-native-google-mobile-ads');
        if (!cancelled) {
          setBanner({ BannerAd: ads.BannerAd, size: ads.BannerAdSize.ANCHORED_ADAPTIVE_BANNER });
        }
      } catch {
        // Not available in Expo Go; nothing renders and the layout is unchanged.
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [unitId]);

  if (!unitId || !Banner) return null;

  return (
    <View style={styles.wrap}>
      <Banner.BannerAd unitId={unitId} size={Banner.size} />
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    alignItems: 'center',
    paddingVertical: 8,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: theme.border,
  },
});
