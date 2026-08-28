import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { Platform } from 'react-native';
import { api } from './api';

export interface AdConfig {
  showAds: boolean;
  plan: string;
  placements: Array<{
    slot: string;
    network: string;
    unitIdIos: string;
    unitIdAndroid: string;
    minIntervalSec: number;
  }>;
}

/**
 * Ad configuration, resolved by the server for this viewer.
 *
 * The client never decides whether to show an ad. A subscriber on a tier that
 * paid to be ad-free simply receives no placements — there is no unit id in the
 * payload to render even if the code tried.
 */
export function useAdConfig() {
  return useQuery({
    queryKey: ['ads'],
    queryFn: () => api<AdConfig>('/ads/config'),
    staleTime: 5 * 60_000,
  });
}

export function useAdUnit(slot: string): string | null {
  const { data } = useAdConfig();
  if (!data?.showAds) return null;

  const placement = data.placements.find((p) => p.slot === slot);
  if (!placement) return null;

  const unit = Platform.OS === 'ios' ? placement.unitIdIos : placement.unitIdAndroid;
  return unit || null;
}

/**
 * Ask for tracking permission before any personalised ad loads.
 *
 * Apple guideline 5.1.2(i) requires the App Tracking Transparency prompt before
 * tracking, and shipping AdMob without it is a routine rejection. Only asked of
 * users who will actually see ads — prompting a paying subscriber for tracking
 * they gain nothing from would be gratuitous.
 */
export function useTrackingPermission(enabled: boolean): void {
  useEffect(() => {
    if (!enabled || Platform.OS === 'web') return;

    void (async () => {
      try {
        const tracking = await import('expo-tracking-transparency');
        const { status } = await tracking.getTrackingPermissionsAsync();
        if (status === 'undetermined') {
          await tracking.requestTrackingPermissionsAsync();
        }
      } catch {
        // The module is absent in Expo Go; ads are not shown there anyway.
      }
    })();
  }, [enabled]);
}
