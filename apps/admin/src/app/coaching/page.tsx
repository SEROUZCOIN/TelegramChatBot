'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, formatDate } from '@/lib/api';

interface Session {
  id: string;
  status: string;
  scheduledAt: string;
  durationMin: number;
  topic: string;
  roomUrl: string | null;
  student: { id: string; displayName: string; email: string };
  coach: { id: string; displayName: string } | null;
}

const STATUSES = ['REQUESTED', 'SCHEDULED', 'LIVE', 'COMPLETED', 'CANCELLED', 'NO_SHOW'] as const;

export default function CoachingPage() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-coaching'],
    queryFn: () => api<Session[]>('/admin/coaching/sessions'),
  });

  const update = useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) =>
      api(`/admin/coaching/sessions/${id}`, { method: 'PUT', body: JSON.stringify({ status }) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-coaching'] }),
  });

  return (
    <>
      <h2>Coaching</h2>
      <p className="lede">
        One-to-one only. That is what keeps the Pro and Ultra tiers eligible for external payment
        under Apple guideline 3.1.3(d) — group sessions would not qualify.
      </p>

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Student</th>
              <th>Coach</th>
              <th>Topic</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr>
                <td colSpan={6} className="empty">
                  Loading…
                </td>
              </tr>
            )}
            {(data ?? []).length === 0 && !isLoading && (
              <tr>
                <td colSpan={6} className="empty">
                  No sessions booked.
                </td>
              </tr>
            )}
            {(data ?? []).map((s) => (
              <tr key={s.id}>
                <td>
                  {formatDate(s.scheduledAt)}
                  <br />
                  <span className="muted">{s.durationMin} min</span>
                </td>
                <td>
                  {s.student.displayName}
                  <br />
                  <span className="muted mono">{s.student.email}</span>
                </td>
                <td>{s.coach?.displayName ?? <span className="muted">unassigned</span>}</td>
                <td className="muted">{s.topic || '—'}</td>
                <td>
                  <span className="badge">{s.status}</span>
                </td>
                <td>
                  <select
                    value={s.status}
                    onChange={(e) => update.mutate({ id: s.id, status: e.target.value })}
                  >
                    {STATUSES.map((st) => (
                      <option key={st} value={st}>
                        {st}
                      </option>
                    ))}
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
