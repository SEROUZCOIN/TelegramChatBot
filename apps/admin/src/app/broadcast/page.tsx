'use client';

import { useMutation } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '@/lib/api';

const PLANS = ['SIGNALS', 'NORMAL', 'PRO', 'ULTRA'] as const;

export default function BroadcastPage() {
  const [pushAudience, setPushAudience] = useState<string[]>([]);
  const [tgAudience, setTgAudience] = useState<string[]>([]);
  const [result, setResult] = useState<string | null>(null);

  const push = useMutation({
    mutationFn: (body: { title: string; body: string; deepLink: string }) =>
      api<{ id: string }>('/admin/push/campaigns', {
        method: 'POST',
        body: JSON.stringify({ ...body, audiencePlans: pushAudience, scheduledAt: null }),
      }),
    onSuccess: () => setResult('Push campaign sent.'),
  });

  const telegram = useMutation({
    mutationFn: (text: string) =>
      api<{ sent: number }>('/admin/telegram/broadcast', {
        method: 'POST',
        body: JSON.stringify({ text, audiencePlans: tgAudience }),
      }),
    onSuccess: (r) => setResult(`Telegram broadcast sent to ${r.sent} chats.`),
  });

  const toggle = (list: string[], set: (v: string[]) => void, code: string) =>
    set(list.includes(code) ? list.filter((c) => c !== code) : [...list, code]);

  return (
    <>
      <h2>Push &amp; Telegram</h2>
      <p className="lede">Selecting no tier sends to everyone.</p>

      {result && <div className="notice">{result}</div>}
      {(push.error || telegram.error) && (
        <div className="notice error">
          {((push.error ?? telegram.error) as Error).message}
        </div>
      )}

      <div className="grid cols-2">
        <div className="card">
          <h3>Push notification</h3>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              push.mutate({
                title: String(f.get('title')),
                body: String(f.get('body')),
                deepLink: String(f.get('deepLink') ?? ''),
              });
            }}
          >
            <div className="field">
              <label htmlFor="ptitle">Title</label>
              <input id="ptitle" name="title" required maxLength={80} />
            </div>
            <div className="field">
              <label htmlFor="pbody">Body</label>
              <textarea id="pbody" name="body" rows={3} required maxLength={300} />
            </div>
            <div className="field">
              <label htmlFor="pdeep">Deep link (optional)</label>
              <input id="pdeep" name="deepLink" placeholder="/signals" className="mono" />
            </div>
            <div className="field">
              <label>Audience</label>
              <div style={{ display: 'flex', gap: 6 }}>
                {PLANS.map((c) => (
                  <button
                    key={c}
                    type="button"
                    className={pushAudience.includes(c) ? 'sm' : 'ghost sm'}
                    onClick={() => toggle(pushAudience, setPushAudience, c)}
                  >
                    {c}
                  </button>
                ))}
              </div>
            </div>
            <button type="submit" disabled={push.isPending}>
              {push.isPending ? 'Sending…' : 'Send push'}
            </button>
          </form>
        </div>

        <div className="card">
          <h3>Telegram broadcast</h3>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              telegram.mutate(String(new FormData(e.currentTarget).get('text')));
            }}
          >
            <div className="field">
              <label htmlFor="ttext">Message (Markdown)</label>
              <textarea id="ttext" name="text" rows={7} required maxLength={4000} />
            </div>
            <div className="field">
              <label>Audience</label>
              <div style={{ display: 'flex', gap: 6 }}>
                {PLANS.map((c) => (
                  <button
                    key={c}
                    type="button"
                    className={tgAudience.includes(c) ? 'sm' : 'ghost sm'}
                    onClick={() => toggle(tgAudience, setTgAudience, c)}
                  >
                    {c}
                  </button>
                ))}
              </div>
            </div>
            <button type="submit" disabled={telegram.isPending}>
              {telegram.isPending ? 'Sending…' : 'Send broadcast'}
            </button>
          </form>
        </div>
      </div>
    </>
  );
}
