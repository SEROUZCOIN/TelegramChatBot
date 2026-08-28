import { useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { api } from '@/lib/api';
import { theme } from '@/lib/theme';
import { Badge, Card, EmptyState, ErrorState, Loading } from '@/components/ui';

interface Lesson {
  id: string;
  title: string;
  description: string;
  durationSec: number;
  order: number;
  isFreePreview: boolean;
  playable: boolean;
}

interface Course {
  id: string;
  title: string;
  slug: string;
  description: string;
  level: string;
  minPlan: string;
  unlocked: boolean;
  lessonCount: number;
  totalDurationSec: number;
  lessons: Lesson[];
}

export default function AcademyTab() {
  const router = useRouter();

  const { data, isLoading, error } = useQuery({
    queryKey: ['courses'],
    queryFn: () => api<{ items: Course[]; viewerPlan: string }>('/courses'),
  });

  if (isLoading) return <Loading />;
  if (error) return <ErrorState message={(error as Error).message} />;

  const courses = data?.items ?? [];
  if (!courses.length) {
    return <EmptyState title="No courses published yet" hint="New material appears here." />;
  }

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.scroll}>
      {courses.map((course) => (
        <Card key={course.id} style={styles.course}>
          <View style={styles.header}>
            <Text style={styles.title}>{course.title}</Text>
            <Badge
              label={course.unlocked ? course.level : `${course.minPlan}+`}
              color={course.unlocked ? theme.buy : theme.warn}
            />
          </View>

          <Text style={styles.description}>{course.description}</Text>
          <Text style={styles.meta}>
            {course.lessonCount} lesson{course.lessonCount === 1 ? '' : 's'} ·{' '}
            {Math.round(course.totalDurationSec / 60)} minutes
          </Text>

          <View style={styles.lessons}>
            {course.lessons.map((lesson) => (
              <Pressable
                key={lesson.id}
                disabled={!lesson.playable}
                onPress={() => router.push(`/lesson/${lesson.id}`)}
                style={({ pressed }) => [styles.lesson, pressed && { opacity: 0.8 }]}
              >
                <Text style={[styles.lessonIcon, !lesson.playable && { color: theme.muted }]}>
                  {lesson.playable ? '▶' : '🔒'}
                </Text>
                <View style={{ flex: 1 }}>
                  <Text
                    style={[styles.lessonTitle, !lesson.playable && { color: theme.muted }]}
                  >
                    {lesson.title}
                  </Text>
                  <Text style={styles.lessonMeta}>
                    {Math.round(lesson.durationSec / 60)} min
                    {lesson.isFreePreview ? ' · free preview' : ''}
                  </Text>
                </View>
              </Pressable>
            ))}
          </View>

          {!course.unlocked && (
            <Pressable onPress={() => router.push('/plans')} style={styles.upsell}>
              <Text style={styles.upsellText}>
                Included with the {course.minPlan} plan — tap to see plans
              </Text>
            </Pressable>
          )}
        </Card>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: theme.bg },
  scroll: { padding: 14, paddingBottom: 24 },
  course: { marginBottom: 14 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 },
  title: { color: theme.text, fontSize: 17, fontWeight: '800', flex: 1 },
  description: { color: theme.muted, fontSize: 13, lineHeight: 19, marginTop: 6 },
  meta: { color: theme.muted, fontSize: 11, marginTop: 6 },
  lessons: { marginTop: 12, gap: 2 },
  lesson: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 9,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: theme.border,
  },
  lessonIcon: { color: theme.accent, fontSize: 13, width: 18 },
  lessonTitle: { color: theme.text, fontSize: 14, fontWeight: '600' },
  lessonMeta: { color: theme.muted, fontSize: 11, marginTop: 1 },
  upsell: {
    marginTop: 12,
    padding: 11,
    borderRadius: 10,
    backgroundColor: `${theme.accent}18`,
    borderWidth: 1,
    borderColor: theme.accent,
  },
  upsellText: { color: theme.text, fontSize: 13, fontWeight: '600', textAlign: 'center' },
});
