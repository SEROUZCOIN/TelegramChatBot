import { useQuery } from '@tanstack/react-query';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEvent } from 'expo';
import { useVideoPlayer, VideoView } from 'expo-video';
import { StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { theme } from '@/lib/theme';
import { Button, Card, ErrorState, Loading } from '@/components/ui';

interface Playback {
  lessonId: string;
  hls: string;
  dash: string;
  thumbnail: string;
  expiresAt: string;
}

/**
 * Lesson playback.
 *
 * The URL played here is minted per request, scoped to this viewer, and expires
 * — the underlying Cloudflare Stream UID never reaches the device. That matters
 * because the video library is the entire value of the Normal plan: a permanent
 * URL, once shared, would give it away.
 */
export default function LessonScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();

  const { data, isLoading, error } = useQuery({
    queryKey: ['playback', id],
    queryFn: () => api<Playback>(`/courses/lessons/${id}/playback`),
    enabled: Boolean(id),
    // The signed token is short-lived, so this must not be served from cache
    // on a later visit.
    staleTime: 0,
    gcTime: 0,
    retry: false,
  });

  const player = useVideoPlayer(data?.hls ?? null, (p) => {
    p.timeUpdateEventInterval = 10;
  });

  const { status } = useEvent(player, 'statusChange', { status: player.status });

  if (isLoading) return <Loading label="Preparing playback…" />;

  if (error) {
    const body = (error as { body?: { requiredPlan?: string; currentPlan?: string } }).body;
    return (
      <View style={styles.screen}>
        <Card style={{ margin: 16 }}>
          <Text style={styles.lockedTitle}>
            {body?.requiredPlan
              ? `This lesson is part of the ${body.requiredPlan} plan`
              : 'This lesson is not available'}
          </Text>
          <Text style={styles.lockedBody}>
            {body?.requiredPlan
              ? `You are on ${body.currentPlan ?? 'the free tier'}. Upgrade to watch the full library.`
              : (error as Error).message}
          </Text>
          {body?.requiredPlan && (
            <>
              <View style={{ height: 14 }} />
              <Button label="See plans" onPress={() => router.push('/plans')} />
            </>
          )}
        </Card>
      </View>
    );
  }

  if (!data) return null;

  return (
    <View style={styles.screen}>
      <VideoView
        player={player}
        style={styles.video}
        fullscreenOptions={{ enable: true }}
        allowsPictureInPicture
        contentFit="contain"
      />

      {status === 'error' && (
        <ErrorState message="Playback failed. Your access link may have expired — reopen the lesson." />
      )}

      <View style={styles.info}>
        <Text style={styles.note}>
          Your playback link is personal and expires{' '}
          {new Date(data.expiresAt).toLocaleTimeString('en-GB', {
            hour: '2-digit',
            minute: '2-digit',
          })}
          . Reopen the lesson to get a fresh one.
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  video: { width: '100%', aspectRatio: 16 / 9, backgroundColor: '#000' },
  info: { padding: 16 },
  note: { color: theme.muted, fontSize: 12, lineHeight: 18 },
  lockedTitle: { color: theme.text, fontSize: 17, fontWeight: '700' },
  lockedBody: { color: theme.muted, fontSize: 14, lineHeight: 21, marginTop: 6 },
});
