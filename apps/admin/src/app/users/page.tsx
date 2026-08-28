'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, formatDate } from '@/lib/api';

interface AdminUser {
  id: string;
  email: string;
  displayName: string;
  role: string;
  isBanned: boolean;
  deletedAt: string | null;
  createdAt: string;
  riskDisclaimerAcceptedAt: string | null;
  subscriptions: Array<{ expiresAt: string | null; plan: { code: string } }>;
}

export default function UsersPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState('');
  const [granting, setGranting] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-users', q],
    queryFn: () => api<AdminUser[]>(`/admin/users?q=${encodeURIComponent(q)}&take=100`),
  });

  const grant = useMutation({
    mutationFn: ({ id, planCode, days }: { id: string; planCode: string; days: number | null }) =>
      api(`/admin/users/${id}/grant`, {
        method: 'POST',
        body: JSON.stringify({ planCode, durationDays: days, reason: 'Granted from admin panel' }),
      }),
    onSuccess: () => {
      setGranting(null);
      qc.invalidateQueries({ queryKey: ['admin-users'] });
    },
  });

  const ban = useMutation({
    mutationFn: ({ id, banned }: { id: string; banned: boolean }) =>
      api(`/admin/users/${id}/ban`, { method: 'POST', body: JSON.stringify({ banned }) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  return (
    <>
      <h2>Users</h2>
      <p className="lede">Granting a plan by hand is audited — it hands out paid access.</p>

      <div className="field" style={{ maxWidth: 320 }}>
        <label htmlFor="search">Search</label>
        <input
          id="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="email or name"
        />
      </div>

      {grant.error && <div className="notice error">{(grant.error as Error).message}</div>}

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Plan</th>
              <th>Disclaimer</th>
              <th>Joined</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr>
                <td colSpan={5} className="empty">
                  Loading…
                </td>
              </tr>
            )}
            {(data ?? []).map((u) => (
              <tr key={u.id}>
                <td>
                  {u.displayName}
                  {u.role !== 'USER' && <span className="badge"> {u.role}</span>}
                  {u.isBanned && <span className="badge loss"> banned</span>}
                  {u.deletedAt && <span className="badge"> deleted</span>}
                  <br />
                  <span className="muted mono">{u.email}</span>
                </td>
                <td>
                  {u.subscriptions.length === 0 ? (
                    <span className="muted">Free</span>
                  ) : (
                    u.subscriptions.map((s) => (
                      <div key={s.plan.code}>
                        <span className="badge">{s.plan.code}</span>{' '}
                        <span className="muted">
                          {s.expiresAt ? `until ${formatDate(s.expiresAt)}` : 'lifetime'}
                        </span>
                      </div>
                    ))
                  )}
                </td>
                <td>
                  {u.riskDisclaimerAcceptedAt ? (
                    <span className="badge win">accepted</span>
                  ) : (
                    <span className="badge warn">not yet</span>
                  )}
                </td>
                <td className="muted">{formatDate(u.createdAt)}</td>
                <td>
                  {granting === u.id ? (
                    <div className="row" style={{ gap: 4 }}>
                      {(['SIGNALS', 'NORMAL', 'PRO', 'ULTRA'] as const).map((code) => (
                        <button
                          key={code}
                          className="ghost sm"
                          disabled={grant.isPending}
                          onClick={() =>
                            grant.mutate({
                              id: u.id,
                              planCode: code,
                              // Coaching tiers are bought once and never lapse.
                              days: code === 'PRO' || code === 'ULTRA' ? null : 30,
                            })
                          }
                        >
                          {code}
                        </button>
                      ))}
                      <button className="ghost sm" onClick={() => setGranting(null)}>
                        Cancel
                      </button>
                    </div>
                  ) : (
                    <div className="row" style={{ gap: 4 }}>
                      <button className="ghost sm" onClick={() => setGranting(u.id)}>
                        Grant plan
                      </button>
                      <button
                        className="ghost sm"
                        onClick={() => ban.mutate({ id: u.id, banned: !u.isBanned })}
                      >
                        {u.isBanned ? 'Unban' : 'Ban'}
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
