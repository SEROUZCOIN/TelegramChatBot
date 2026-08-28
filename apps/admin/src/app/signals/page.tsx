'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import Link from 'next/link';
import { useState } from 'react';
import {
  availableUpdateActions,
  STATUS_LABEL,
  UPDATE_LABEL,
  type SignalStatus,
  type SignalUpdateType,
} from '@tsp/shared';
import { api, formatDate } from '@/lib/api';

interface AdminSignal {
  id: string;
  symbol: string;
  direction: 'BUY' | 'SELL';
  status: SignalStatus;
  minPlan: string;
  timeframe: string;
  entryLow: number;
  entryHigh: number;
  sl: number;
  resultPips: number | null;
  publishedAt: string | null;
  createdAt: string;
  metrics: { slPips: number; maxRR: number | null };
  updates: Array<{ id: string; type: SignalUpdateType; note: string; createdAt: string }>;
}

const badgeFor = (s: SignalStatus): string =>
  s === 'CLOSED_WIN' ? 'badge win' : s === 'CLOSED_LOSS' ? 'badge loss' : 'badge';

export default function SignalsPage() {
  const qc = useQueryClient();
  const [expanded, setExpanded] = useState<string | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-signals'],
    queryFn: () => api<{ items: AdminSignal[] }>('/admin/signals?limit=50'),
  });

  const publish = useMutation({
    mutationFn: (id: string) => api(`/admin/signals/${id}/publish`, { method: 'POST' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-signals'] }),
  });

  const update = useMutation({
    mutationFn: ({ id, type, price }: { id: string; type: SignalUpdateType; price?: number }) =>
      api(`/admin/signals/${id}/updates`, {
        method: 'POST',
        body: JSON.stringify({ type, note: '', price: price ?? null }),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-signals'] }),
  });

  if (isLoading) return <div className="empty">Loading…</div>;
  if (error) return <div className="notice error">{(error as Error).message}</div>;

  const items = data?.items ?? [];

  return (
    <>
      <h2>Signals</h2>
      <p className="lede">
        Each update is pushed to subscribers and edits the existing Telegram message in place.
      </p>

      <div style={{ marginBottom: 14 }}>
        <Link href="/signals/new" className="btn" style={{ display: 'inline-block' }}>
          New signal
        </Link>
      </div>

      {update.error && <div className="notice error">{(update.error as Error).message}</div>}

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Symbol</th>
              <th>Status</th>
              <th>Tier</th>
              <th className="num">Risk</th>
              <th className="num">Result</th>
              <th>Published</th>
              <th>Console</th>
            </tr>
          </thead>
          <tbody>
            {items.length === 0 && (
              <tr>
                <td colSpan={7} className="empty">
                  No signals yet.
                </td>
              </tr>
            )}

            {items.map((s) => {
              const actions = availableUpdateActions(s.status).filter((a) => a !== 'COMMENT');
              const isOpen = expanded === s.id;

              return (
                <>
                  <tr key={s.id}>
                    <td>
                      <button
                        className="ghost sm"
                        onClick={() => setExpanded(isOpen ? null : s.id)}
                        style={{ marginRight: 8 }}
                      >
                        {isOpen ? '−' : '+'}
                      </button>
                      <strong>{s.symbol}</strong>{' '}
                      <span className={`badge ${s.direction.toLowerCase()}`}>{s.direction}</span>{' '}
                      <span className="muted">{s.timeframe}</span>
                    </td>
                    <td>
                      <span className={badgeFor(s.status)}>{STATUS_LABEL[s.status]}</span>
                    </td>
                    <td>
                      <span className="badge">{s.minPlan}</span>
                    </td>
                    <td className="num mono">{s.metrics.slPips}p</td>
                    <td
                      className="num mono"
                      style={{
                        color:
                          s.resultPips == null
                            ? 'var(--muted)'
                            : s.resultPips >= 0
                              ? 'var(--buy)'
                              : 'var(--sell)',
                      }}
                    >
                      {s.resultPips == null ? '—' : `${s.resultPips > 0 ? '+' : ''}${s.resultPips}p`}
                    </td>
                    <td className="muted">{formatDate(s.publishedAt)}</td>
                    <td>
                      {s.status === 'DRAFT' ? (
                        <button className="sm" onClick={() => publish.mutate(s.id)}>
                          Publish
                        </button>
                      ) : actions.length === 0 ? (
                        <span className="muted">Closed</span>
                      ) : (
                        <div className="row" style={{ gap: 4 }}>
                          {actions.slice(0, 4).map((a) => (
                            <button
                              key={a}
                              className="ghost sm"
                              disabled={update.isPending}
                              onClick={() => update.mutate({ id: s.id, type: a })}
                              title={UPDATE_LABEL[a]}
                            >
                              {shortLabel(a)}
                            </button>
                          ))}
                        </div>
                      )}
                    </td>
                  </tr>

                  {isOpen && (
                    <tr key={`${s.id}-detail`}>
                      <td colSpan={7} style={{ background: 'var(--bg)' }}>
                        <div style={{ display: 'flex', gap: 32, padding: '8px 4px' }}>
                          <div>
                            <h3 style={{ fontSize: 12, color: 'var(--muted)', margin: '0 0 6px' }}>
                              Levels
                            </h3>
                            <div className="mono">
                              Entry {s.entryLow}
                              {s.entryHigh !== s.entryLow ? `–${s.entryHigh}` : ''}
                              <br />
                              Stop {s.sl} ({s.metrics.slPips} pips)
                              <br />
                              {s.metrics.maxRR ? `Planned ${s.metrics.maxRR}R` : ''}
                            </div>
                          </div>
                          <div style={{ flex: 1 }}>
                            <h3 style={{ fontSize: 12, color: 'var(--muted)', margin: '0 0 6px' }}>
                              Timeline
                            </h3>
                            {s.updates.length === 0 ? (
                              <p className="muted">No updates yet.</p>
                            ) : (
                              <ol style={{ margin: 0, paddingLeft: 18 }}>
                                {s.updates.map((u) => (
                                  <li key={u.id}>
                                    {UPDATE_LABEL[u.type]}{' '}
                                    <span className="muted">{formatDate(u.createdAt)}</span>
                                    {u.note && <span className="muted"> — {u.note}</span>}
                                  </li>
                                ))}
                              </ol>
                            )}
                          </div>
                          <div>
                            <h3 style={{ fontSize: 12, color: 'var(--muted)', margin: '0 0 6px' }}>
                              All actions
                            </h3>
                            <div className="row" style={{ gap: 4, maxWidth: 260 }}>
                              {availableUpdateActions(s.status).map((a) => (
                                <button
                                  key={a}
                                  className="ghost sm"
                                  disabled={update.isPending}
                                  onClick={() => update.mutate({ id: s.id, type: a })}
                                >
                                  {UPDATE_LABEL[a]}
                                </button>
                              ))}
                            </div>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}

function shortLabel(t: SignalUpdateType): string {
  const map: Partial<Record<SignalUpdateType, string>> = {
    ENTRY_HIT: 'Entry',
    MOVED_TO_BE: '→ BE',
    TP1_HIT: 'TP1',
    TP2_HIT: 'TP2',
    TP3_HIT: 'TP3',
    SL_HIT: 'SL',
    CLOSE_WIN: 'Close +',
    CLOSE_LOSS: 'Close −',
    CANCELLED: 'Cancel',
  };
  return map[t] ?? t;
}
