'use client';

import { useEffect, useState } from 'react';
import { api, getToken, login, setToken } from '@/lib/api';

interface Me {
  id: string;
  email: string;
  displayName: string;
  role: 'USER' | 'COACH' | 'ADMIN';
}

/**
 * Wraps the whole panel in an admin-only session check.
 *
 * The role is verified against the API rather than read out of the token
 * client-side. That is deliberate: the server enforces the role on every
 * request anyway, and checking here keeps the UI honest about what it is
 * showing rather than trusting a decoded claim.
 */
export function AuthGate({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<'loading' | 'anon' | 'ok' | 'forbidden'>('loading');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!getToken()) return setState('anon');

    api<Me>('/me')
      .then((me) => setState(me.role === 'ADMIN' ? 'ok' : 'forbidden'))
      .catch(() => setState('anon'));
  }, []);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    const form = new FormData(e.currentTarget);
    try {
      await login(String(form.get('email')), String(form.get('password')));
      const me = await api<Me>('/me');
      setState(me.role === 'ADMIN' ? 'ok' : 'forbidden');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed');
    } finally {
      setBusy(false);
    }
  }

  if (state === 'loading') {
    return <div className="empty">Checking your session…</div>;
  }

  if (state === 'forbidden') {
    return (
      <div style={{ maxWidth: 380, margin: '18vh auto' }}>
        <div className="notice error">
          That account is signed in but is not an administrator.
        </div>
        <button
          className="ghost"
          onClick={() => {
            setToken(null);
            setState('anon');
          }}
        >
          Sign in as someone else
        </button>
      </div>
    );
  }

  if (state === 'anon') {
    return (
      <div style={{ maxWidth: 360, margin: '16vh auto' }}>
        <h2 style={{ marginBottom: 4 }}>Signals Admin</h2>
        <p className="lede">Sign in with an administrator account.</p>

        {error && <div className="notice error">{error}</div>}

        <form onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input id="email" name="email" type="email" required autoComplete="username" />
          </div>
          <div className="field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
            />
          </div>
          <button type="submit" disabled={busy} style={{ width: '100%' }}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    );
  }

  return <>{children}</>;
}
