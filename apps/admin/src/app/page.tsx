'use client';

import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { api, formatMoney } from '@/lib/api';

interface Overview {
  windowDays: number;
  revenue: {
    mrrCents: number;
    windowRevenueCents: number;
    oneTimeCents: number;
    byProvider: Record<string, number>;
  };
  subscribers: Array<{ plan: string; count: number }>;
  signals: {
    total: number;
    open: number;
    wins: number;
    losses: number;
    breakEven: number;
    winRate: number | null;
    totalPips: number;
    profitFactor: number | null;
    currentStreak: number;
    bestStreak: number;
  };
  queue: { paymentsAwaitingReview: number; upcomingCoaching: number };
  growth: { newUsers: number; activeDevices24h: number };
}

export default function DashboardPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['dashboard'],
    queryFn: () => api<Overview>('/admin/dashboard?days=30'),
  });

  if (isLoading) return <div className="empty">Loading…</div>;
  if (error) return <div className="notice error">{(error as Error).message}</div>;
  if (!data) return null;

  const s = data.signals;

  return (
    <>
      <h2>Dashboard</h2>
      <p className="lede">Last {data.windowDays} days.</p>

      {data.queue.paymentsAwaitingReview > 0 && (
        <div className="notice warn">
          <strong>{data.queue.paymentsAwaitingReview}</strong> payment
          {data.queue.paymentsAwaitingReview === 1 ? '' : 's'} waiting on your approval — these
          buyers have paid but do not have access yet.{' '}
          <Link href="/payments">Open the queue →</Link>
        </div>
      )}

      <div className="grid cols-4">
        <div className="card">
          <h3>Recurring revenue</h3>
          <div className="stat">{formatMoney(data.revenue.mrrCents)}</div>
          <div className="stat-note">per month, from active subscriptions</div>
        </div>
        <div className="card">
          <h3>Collected ({data.windowDays}d)</h3>
          <div className="stat">{formatMoney(data.revenue.windowRevenueCents)}</div>
          <div className="stat-note">
            {formatMoney(data.revenue.oneTimeCents)} of it one-time coaching
          </div>
        </div>
        <div className="card">
          <h3>Win rate</h3>
          <div className="stat">{s.winRate === null ? '—' : `${s.winRate}%`}</div>
          <div className="stat-note">
            {s.wins}W / {s.losses}L / {s.breakEven} scratch
          </div>
        </div>
        <div className="card">
          <h3>Net pips</h3>
          <div className="stat" style={{ color: s.totalPips >= 0 ? 'var(--buy)' : 'var(--sell)' }}>
            {s.totalPips > 0 ? '+' : ''}
            {s.totalPips}
          </div>
          <div className="stat-note">
            {s.profitFactor === null ? 'no losses yet' : `profit factor ${s.profitFactor}`}
          </div>
        </div>
      </div>

      <div className="grid cols-2" style={{ marginTop: 14 }}>
        <div className="card">
          <h3>Subscribers by plan</h3>
          {data.subscribers.length === 0 ? (
            <p className="muted">No active subscriptions yet.</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Plan</th>
                  <th className="num">Active</th>
                </tr>
              </thead>
              <tbody>
                {data.subscribers.map((row) => (
                  <tr key={row.plan}>
                    <td>
                      <span className="badge">{row.plan}</span>
                    </td>
                    <td className="num">{row.count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div className="card">
          <h3>Activity</h3>
          <table>
            <tbody>
              <tr>
                <td>Open signals</td>
                <td className="num">{s.open}</td>
              </tr>
              <tr>
                <td>Signals published ({data.windowDays}d)</td>
                <td className="num">{s.total}</td>
              </tr>
              <tr>
                <td>Current streak</td>
                <td className="num">
                  {s.currentStreak === 0
                    ? '—'
                    : `${Math.abs(s.currentStreak)} ${s.currentStreak > 0 ? 'win' : 'loss'}${
                        Math.abs(s.currentStreak) === 1 ? '' : 'es'
                      }`}
                </td>
              </tr>
              <tr>
                <td>New users</td>
                <td className="num">{data.growth.newUsers}</td>
              </tr>
              <tr>
                <td>Devices active (24h)</td>
                <td className="num">{data.growth.activeDevices24h}</td>
              </tr>
              <tr>
                <td>Upcoming coaching sessions</td>
                <td className="num">{data.queue.upcomingCoaching}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
