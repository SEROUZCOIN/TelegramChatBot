'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, formatDate, formatMoney } from '@/lib/api';

interface PendingPayment {
  id: string;
  provider: string;
  amountCents: number;
  currency: string;
  reference: string | null;
  proofUrl: string | null;
  createdAt: string;
  plan: { code: string; name: string };
  user: { id: string; email: string; displayName: string };
}

/**
 * The manual approval queue.
 *
 * Bank transfers and unbrokered crypto land here. Everyone in this list has
 * paid and does not yet have access, so it is the one screen where a delay
 * costs a real customer real time.
 */
export default function PaymentsPage() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['pending-payments'],
    queryFn: () => api<PendingPayment[]>('/admin/payments/pending'),
  });

  const review = useMutation({
    mutationFn: ({ id, approve }: { id: string; approve: boolean }) =>
      api(`/admin/payments/${id}/review`, {
        method: 'POST',
        body: JSON.stringify({ approve, note: approve ? 'Verified' : 'Could not verify' }),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['pending-payments'] });
      qc.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });

  if (isLoading) return <div className="empty">Loading…</div>;
  const items = data ?? [];

  return (
    <>
      <h2>Payment queue</h2>
      <p className="lede">
        Approving grants the plan immediately. Everyone here has paid and is waiting.
      </p>

      {review.error && <div className="notice error">{(review.error as Error).message}</div>}

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Buyer</th>
              <th>Plan</th>
              <th className="num">Amount</th>
              <th>Rail</th>
              <th>Reference</th>
              <th>Submitted</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {items.length === 0 && (
              <tr>
                <td colSpan={7} className="empty">
                  Nothing waiting. Every paid customer has access.
                </td>
              </tr>
            )}
            {items.map((p) => (
              <tr key={p.id}>
                <td>
                  {p.user.displayName}
                  <br />
                  <span className="muted mono">{p.user.email}</span>
                </td>
                <td>
                  <span className="badge">{p.plan.code}</span>
                </td>
                <td className="num mono">{formatMoney(p.amountCents, p.currency)}</td>
                <td>
                  <span className="badge">{p.provider}</span>
                </td>
                <td className="mono">
                  {p.reference ?? <span className="muted">none given</span>}
                  {p.proofUrl && (
                    <>
                      {' '}
                      <a href={p.proofUrl} target="_blank" rel="noreferrer">
                        proof
                      </a>
                    </>
                  )}
                </td>
                <td className="muted">{formatDate(p.createdAt)}</td>
                <td>
                  <div className="row" style={{ gap: 6 }}>
                    <button
                      className="sm"
                      disabled={review.isPending}
                      onClick={() => review.mutate({ id: p.id, approve: true })}
                    >
                      Approve
                    </button>
                    <button
                      className="danger sm"
                      disabled={review.isPending}
                      onClick={() => review.mutate({ id: p.id, approve: false })}
                    >
                      Reject
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
