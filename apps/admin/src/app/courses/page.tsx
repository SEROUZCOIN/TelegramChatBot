'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '@/lib/api';

interface Lesson {
  id: string;
  title: string;
  description: string;
  videoUid: string | null;
  durationSec: number;
  order: number;
  isFreePreview: boolean;
}

interface Course {
  id: string;
  title: string;
  slug: string;
  description: string;
  level: string;
  minPlan: string;
  isPublished: boolean;
  lessons: Lesson[];
}

export default function CoursesPage() {
  const qc = useQueryClient();
  const [addingTo, setAddingTo] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-courses'],
    queryFn: () => api<Course[]>('/admin/courses'),
  });

  const createCourse = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api('/admin/courses', { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-courses'] }),
  });

  const updateCourse = useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: Record<string, unknown> }) =>
      api(`/admin/courses/${id}`, { method: 'PUT', body: JSON.stringify(patch) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-courses'] }),
  });

  const createLesson = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api('/admin/courses/lessons', { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: () => {
      setAddingTo(null);
      qc.invalidateQueries({ queryKey: ['admin-courses'] });
    },
  });

  return (
    <>
      <h2>Courses</h2>
      <p className="lede">
        The recorded library is what the Normal plan sells, so it is served only through
        short-lived signed URLs — the Cloudflare Stream UID never reaches a client.
      </p>

      {(createCourse.error || createLesson.error) && (
        <div className="notice error">
          {((createCourse.error ?? createLesson.error) as Error).message}
        </div>
      )}

      <div className="card" style={{ marginBottom: 14 }}>
        <h3>New course</h3>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            createCourse.mutate({
              title: String(f.get('title')),
              slug: String(f.get('slug')),
              description: String(f.get('description') ?? ''),
              level: String(f.get('level')),
              minPlan: String(f.get('minPlan')),
              isPublished: false,
            });
            e.currentTarget.reset();
          }}
        >
          <div className="row">
            <div className="field">
              <label htmlFor="ctitle">Title</label>
              <input id="ctitle" name="title" required />
            </div>
            <div className="field">
              <label htmlFor="cslug">Slug</label>
              <input id="cslug" name="slug" required pattern="[a-z0-9\-]+" placeholder="risk-management" />
            </div>
            <div className="field">
              <label htmlFor="clevel">Level</label>
              <select id="clevel" name="level" defaultValue="BEGINNER">
                <option>BEGINNER</option>
                <option>INTERMEDIATE</option>
                <option>ADVANCED</option>
              </select>
            </div>
            <div className="field">
              <label htmlFor="cplan">Minimum plan</label>
              <select id="cplan" name="minPlan" defaultValue="NORMAL">
                <option value="NORMAL">Normal</option>
                <option value="PRO">Pro</option>
                <option value="ULTRA">Ultra</option>
              </select>
            </div>
          </div>
          <div className="field">
            <label htmlFor="cdesc">Description</label>
            <textarea id="cdesc" name="description" rows={2} />
          </div>
          <button type="submit" disabled={createCourse.isPending}>
            Create course
          </button>
        </form>
      </div>

      {isLoading && <div className="empty">Loading…</div>}

      {(data ?? []).map((c) => (
        <div className="card" key={c.id} style={{ marginBottom: 14 }}>
          <h3>
            {c.title} <span className="badge">{c.level}</span>{' '}
            <span className="badge">{c.minPlan}+</span>{' '}
            {c.isPublished ? (
              <span className="badge win">published</span>
            ) : (
              <span className="badge warn">draft</span>
            )}
          </h3>

          <table>
            <thead>
              <tr>
                <th className="num">#</th>
                <th>Lesson</th>
                <th>Video</th>
                <th className="num">Length</th>
                <th>Free preview</th>
              </tr>
            </thead>
            <tbody>
              {c.lessons.map((l) => (
                <tr key={l.id}>
                  <td className="num">{l.order}</td>
                  <td>{l.title}</td>
                  <td className="mono muted">
                    {l.videoUid ? `${l.videoUid.slice(0, 12)}…` : <span className="badge warn">no video</span>}
                  </td>
                  <td className="num">{Math.round(l.durationSec / 60)}m</td>
                  <td>{l.isFreePreview ? <span className="badge win">yes</span> : '—'}</td>
                </tr>
              ))}
              {c.lessons.length === 0 && (
                <tr>
                  <td colSpan={5} className="muted" style={{ padding: 12 }}>
                    No lessons yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>

          <div className="row" style={{ marginTop: 12 }}>
            <button className="ghost sm" onClick={() => setAddingTo(addingTo === c.id ? null : c.id)}>
              {addingTo === c.id ? 'Cancel' : 'Add lesson'}
            </button>
            <button
              className="ghost sm"
              onClick={() => updateCourse.mutate({ id: c.id, patch: { isPublished: !c.isPublished } })}
            >
              {c.isPublished ? 'Unpublish' : 'Publish'}
            </button>
          </div>

          {addingTo === c.id && (
            <form
              style={{ marginTop: 12 }}
              onSubmit={(e) => {
                e.preventDefault();
                const f = new FormData(e.currentTarget);
                createLesson.mutate({
                  courseId: c.id,
                  title: String(f.get('title')),
                  description: String(f.get('description') ?? ''),
                  videoUid: String(f.get('videoUid') ?? '') || null,
                  durationSec: Number(f.get('durationSec') ?? 0),
                  order: c.lessons.length + 1,
                  isFreePreview: f.get('isFreePreview') === 'on',
                });
              }}
            >
              <div className="row">
                <div className="field">
                  <label htmlFor={`lt-${c.id}`}>Title</label>
                  <input id={`lt-${c.id}`} name="title" required />
                </div>
                <div className="field">
                  <label htmlFor={`lv-${c.id}`}>Cloudflare Stream UID</label>
                  <input id={`lv-${c.id}`} name="videoUid" className="mono" />
                </div>
                <div className="field">
                  <label htmlFor={`ld-${c.id}`}>Duration (seconds)</label>
                  <input id={`ld-${c.id}`} name="durationSec" type="number" defaultValue={0} />
                </div>
              </div>
              <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                <input type="checkbox" name="isFreePreview" style={{ width: 'auto' }} />
                Free preview — playable on any tier, including free
              </label>
              <button type="submit" disabled={createLesson.isPending} style={{ marginTop: 8 }}>
                Add lesson
              </button>
            </form>
          )}
        </div>
      ))}
    </>
  );
}
