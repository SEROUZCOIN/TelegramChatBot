'use client';

import { useMutation } from '@tanstack/react-query';
import { useRouter } from 'next/navigation';
import { useMemo, useState } from 'react';
import {
  computeSignalMetrics,
  formatSignalMarkdown,
  validateLevels,
  type TradeDirection,
} from '@tsp/shared';
import { api } from '@/lib/api';

const num = (v: string): number | null => {
  const n = Number(v);
  return v.trim() !== '' && Number.isFinite(n) ? n : null;
};

/**
 * The signal composer.
 *
 * Two things it deliberately does. It validates the levels with the *same*
 * `validateLevels` the API runs, so a stop on the wrong side of entry is caught
 * while you type rather than as a 400 after you submit. And it renders the
 * subscriber's view live from the same formatter the Telegram bot uses — what
 * you see here is what they get, character for character.
 */
export default function NewSignalPage() {
  const router = useRouter();

  const [symbol, setSymbol] = useState('EURUSD');
  const [direction, setDirection] = useState<TradeDirection>('BUY');
  const [orderType, setOrderType] = useState('MARKET');
  const [timeframe, setTimeframe] = useState('H1');
  const [minPlan, setMinPlan] = useState('SIGNALS');
  const [entryLow, setEntryLow] = useState('');
  const [entryHigh, setEntryHigh] = useState('');
  const [sl, setSl] = useState('');
  const [tp1, setTp1] = useState('');
  const [tp2, setTp2] = useState('');
  const [tp3, setTp3] = useState('');
  const [beTrigger, setBeTrigger] = useState('');
  const [pipSize, setPipSize] = useState('');
  const [riskPercent, setRiskPercent] = useState('1');
  const [analysisText, setAnalysisText] = useState('');
  const [error, setError] = useState<string | null>(null);

  const levels = useMemo(() => {
    const lo = num(entryLow);
    const hi = num(entryHigh) ?? lo;
    const stop = num(sl);
    if (lo === null || hi === null || stop === null) return null;

    return {
      symbol: symbol.toUpperCase(),
      direction,
      entryLow: lo,
      entryHigh: hi,
      sl: stop,
      tp1: num(tp1),
      tp2: num(tp2),
      tp3: num(tp3),
      beTrigger: num(beTrigger),
      pipSize: num(pipSize),
    };
  }, [symbol, direction, entryLow, entryHigh, sl, tp1, tp2, tp3, beTrigger, pipSize]);

  const problems = levels ? validateLevels(levels) : [];
  const metrics = levels && problems.length === 0 ? computeSignalMetrics(levels) : null;

  const preview =
    levels && problems.length === 0
      ? formatSignalMarkdown({ ...levels, status: 'PUBLISHED', timeframe, analysisText })
      : null;

  const mutation = useMutation({
    mutationFn: (publishNow: boolean) =>
      api<{ id: string }>('/admin/signals', {
        method: 'POST',
        body: JSON.stringify({
          ...levels,
          orderType,
          timeframe,
          minPlan,
          riskPercent: num(riskPercent),
          analysisText,
          imageIds: [],
          publishNow,
        }),
      }),
    onSuccess: () => router.push('/signals'),
    onError: (err) => setError(err instanceof Error ? err.message : 'Failed to save'),
  });

  const canSubmit = levels !== null && problems.length === 0 && !mutation.isPending;

  return (
    <>
      <h2>New signal</h2>
      <p className="lede">
        Every derived number is computed from the levels — nothing here is typed by hand.
      </p>

      {error && <div className="notice error">{error}</div>}

      <div className="grid cols-2">
        <div className="card">
          <h3>Setup</h3>

          <div className="row">
            <div className="field">
              <label htmlFor="symbol">Symbol</label>
              <input
                id="symbol"
                value={symbol}
                onChange={(e) => setSymbol(e.target.value.toUpperCase())}
              />
            </div>
            <div className="field">
              <label htmlFor="direction">Direction</label>
              <select
                id="direction"
                value={direction}
                onChange={(e) => setDirection(e.target.value as TradeDirection)}
              >
                <option>BUY</option>
                <option>SELL</option>
              </select>
            </div>
          </div>

          <div className="row">
            <div className="field">
              <label htmlFor="orderType">Order type</label>
              <select id="orderType" value={orderType} onChange={(e) => setOrderType(e.target.value)}>
                <option>MARKET</option>
                <option>LIMIT</option>
                <option>STOP</option>
              </select>
            </div>
            <div className="field">
              <label htmlFor="timeframe">Timeframe</label>
              <input id="timeframe" value={timeframe} onChange={(e) => setTimeframe(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="minPlan">Visible from</label>
              <select id="minPlan" value={minPlan} onChange={(e) => setMinPlan(e.target.value)}>
                <option value="SIGNALS">Signals and above</option>
                <option value="NORMAL">Normal and above</option>
                <option value="PRO">Pro and above</option>
                <option value="ULTRA">Ultra only</option>
              </select>
            </div>
          </div>

          <div className="row">
            <div className="field">
              <label htmlFor="entryLow">Entry zone low</label>
              <input id="entryLow" inputMode="decimal" value={entryLow}
                onChange={(e) => setEntryLow(e.target.value)} placeholder="1.0790" />
            </div>
            <div className="field">
              <label htmlFor="entryHigh">Entry zone high</label>
              <input id="entryHigh" inputMode="decimal" value={entryHigh}
                onChange={(e) => setEntryHigh(e.target.value)} placeholder="leave blank for a single price" />
            </div>
          </div>

          <div className="row">
            <div className="field">
              <label htmlFor="sl">Stop loss</label>
              <input id="sl" inputMode="decimal" value={sl} onChange={(e) => setSl(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="be">Move to break-even at</label>
              <input id="be" inputMode="decimal" value={beTrigger}
                onChange={(e) => setBeTrigger(e.target.value)} />
            </div>
          </div>

          <div className="row">
            <div className="field">
              <label htmlFor="tp1">TP1</label>
              <input id="tp1" inputMode="decimal" value={tp1} onChange={(e) => setTp1(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="tp2">TP2</label>
              <input id="tp2" inputMode="decimal" value={tp2} onChange={(e) => setTp2(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="tp3">TP3</label>
              <input id="tp3" inputMode="decimal" value={tp3} onChange={(e) => setTp3(e.target.value)} />
            </div>
          </div>

          <div className="row">
            <div className="field">
              <label htmlFor="risk">Risk %</label>
              <input id="risk" inputMode="decimal" value={riskPercent}
                onChange={(e) => setRiskPercent(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="pipSize">Pip size override</label>
              <input id="pipSize" inputMode="decimal" value={pipSize}
                onChange={(e) => setPipSize(e.target.value)} placeholder="auto" />
            </div>
          </div>

          <div className="field">
            <label htmlFor="analysis">Analysis</label>
            <textarea id="analysis" rows={4} value={analysisText}
              onChange={(e) => setAnalysisText(e.target.value)}
              placeholder="Why this setup, and what invalidates it." />
          </div>

          <div className="row">
            <button onClick={() => mutation.mutate(true)} disabled={!canSubmit}>
              {mutation.isPending ? 'Saving…' : 'Publish now'}
            </button>
            <button className="ghost" onClick={() => mutation.mutate(false)} disabled={!canSubmit}>
              Save as draft
            </button>
          </div>
        </div>

        <div>
          {problems.length > 0 && (
            <div className="notice warn">
              <strong>Check these before publishing</strong>
              <ul style={{ margin: '6px 0 0', paddingLeft: 18 }}>
                {problems.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
            </div>
          )}

          {metrics && (
            <div className="card" style={{ marginBottom: 14 }}>
              <h3>Computed</h3>
              <table>
                <tbody>
                  <tr>
                    <td>Reference entry</td>
                    <td className="num mono">{metrics.entryRef}</td>
                  </tr>
                  <tr>
                    <td>Risk to stop</td>
                    <td className="num mono">{metrics.slPips} pips</td>
                  </tr>
                  {metrics.targets.map((t) => (
                    <tr key={t.level}>
                      <td>TP{t.level}</td>
                      <td className="num mono">
                        {t.pips} pips{t.rr ? ` · ${t.rr}R` : ''}
                      </td>
                    </tr>
                  ))}
                  <tr>
                    <td>Pip size used</td>
                    <td className="num mono">{metrics.pipSize}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          )}

          <div className="card">
            <h3>What subscribers will see</h3>
            {preview ? (
              <pre
                className="mono"
                style={{ whiteSpace: 'pre-wrap', margin: 0, lineHeight: 1.6 }}
              >
                {preview}
              </pre>
            ) : (
              <p className="muted">Fill in entry and stop to see the preview.</p>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
