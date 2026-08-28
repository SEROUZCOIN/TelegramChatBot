'use client';

import { useQuery } from '@tanstack/react-query';
import { api, formatDate } from '@/lib/api';

interface AuditEntry {
  id: string;
  action: string;
  entity: string;
  entityId: string | null;
  after: unknown;
  createdAt: string;
  actor: { id: string; email: string; displayName: string } | null;
}

export default function AuditPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['audit'],
    queryFn: () => api<AuditEntry[]>('/admin/dashboard/audit?take=200'),
  });

  return (
    <>
      <h2>Audit log</h2>
      <p className="lede">
        Who changed a price, approved a payment, or granted access — and when.
      </p>

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Who</th>
              <th>Action</th>
              <th>Entity</th>
              <th>Detail</th>
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
            {(data ?? []).map((e) => (
              <tr key={e.id}>
                <td className="muted">{formatDate(e.createdAt)}</td>
                <td>{e.actor?.displayName ?? <span className="muted">system</span>}</td>
                <td>
                  <span className="badge">{e.action}</span>
                </td>
                <td className="mono muted">
                  {e.entity}
                  {e.entityId ? ` ${e.entityId.slice(0, 8)}` : ''}
                </td>
                <td className="mono muted">
                  {e.after ? JSON.stringify(e.after).slice(0, 90) : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
