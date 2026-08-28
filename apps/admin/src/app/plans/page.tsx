'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, formatMoney } from '@/lib/api';

interface Plan {
  id: string;
  code: string;
  name: string;
  tagline: string;
  priceCents: number;
  currency: string;
  interval: string;
  paymentMode: 'EXTERNAL' | 'IAP' | 'BOTH';
  isActive: boolean;
  sortOrder: number;
}

/**
 * Plan and pricing editor.
 *
 * `paymentMode` is the control that matters here — see the notice in the UI.
 * It is the prepared answer to an App Store rejection, and flipping it is a
 * data change rather than a release.
 */
export default function PlansPage() {
  const qc = useQueryClient();
  const [saved, setSaved] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-plans'],
    queryFn: () => api<Plan[]>('/admin/plans'),
  });

  const update = useMutation({
    mutationFn: ({ code, patch }: { code: string; patch: Partial<Plan> }) =>
      api(`/admin/plans/${code}`, { method: 'PUT', body: JSON.stringify(patch) }),
    onSuccess: (_r, vars) => {
      setSaved(vars.code);
      qc.invalidateQueries({ queryKey: ['admin-plans'] });
      setTimeout(() => setSaved(null), 2500);
    },
  });

  if (isLoading) return <div className="empty">Loading…</div>;
  const plans = (data ?? []).filter((p) => p.code !== 'FREE');

  return (
    <>
      <h2>Plans &amp; pricing</h2>
      <p className="lede">Price changes take effect on the next checkout. Every edit is audited.</p>

      <div className="notice warn">
        <strong>About the payment rail.</strong> Everything runs on{' '}
        <span className="mono">EXTERNAL</span> rails, which keeps roughly 97% of revenue instead of
        a 15–30% store commission. Apple guideline 3.1.3(d) explicitly allows this for the one-to-one
        coaching tiers (Pro, Ultra). The exposure is <strong>Normal</strong>: it sells recorded
        video, and guideline 3.1.1 requires in-app purchase to unlock digital content. If App Review
        objects, switch that one plan to <span className="mono">IAP</span> here — the provider is
        already built and registered, so no code change and no new build is needed.
      </div>

      <div className="grid cols-2">
        {plans.map((plan) => (
          <div className="card" key={plan.id}>
            <h3>
              {plan.name} <span className="badge">{plan.code}</span>
            </h3>

            <p className="muted" style={{ marginTop: -4 }}>
              {plan.tagline}
            </p>

            <div className="row">
              <div className="field">
                <label htmlFor={`price-${plan.code}`}>Price ({plan.currency})</label>
                <input
                  id={`price-${plan.code}`}
                  type="number"
                  defaultValue={plan.priceCents / 100}
                  onBlur={(e) => {
                    const cents = Math.round(Number(e.target.value) * 100);
                    if (Number.isFinite(cents) && cents !== plan.priceCents) {
                      update.mutate({ code: plan.code, patch: { priceCents: cents } });
                    }
                  }}
                />
              </div>

              <div className="field">
                <label htmlFor={`mode-${plan.code}`}>Payment rail</label>
                <select
                  id={`mode-${plan.code}`}
                  value={plan.paymentMode}
                  onChange={(e) =>
                    update.mutate({
                      code: plan.code,
                      patch: { paymentMode: e.target.value as Plan['paymentMode'] },
                    })
                  }
                >
                  <option value="EXTERNAL">External only (keeps ~97%)</option>
                  <option value="IAP">In-app purchase only</option>
                  <option value="BOTH">Both</option>
                </select>
              </div>
            </div>

            <div className="row" style={{ alignItems: 'center' }}>
              <div className="muted">
                {formatMoney(plan.priceCents, plan.currency)}{' '}
                {plan.interval === 'ONE_TIME' ? 'one-time' : `per ${plan.interval.toLowerCase()}`}
              </div>
              <label style={{ display: 'flex', gap: 6, alignItems: 'center', margin: 0 }}>
                <input
                  type="checkbox"
                  style={{ width: 'auto' }}
                  checked={plan.isActive}
                  onChange={(e) =>
                    update.mutate({ code: plan.code, patch: { isActive: e.target.checked } })
                  }
                />
                Sellable
              </label>
            </div>

            {saved === plan.code && <div className="badge win">Saved</div>}
          </div>
        ))}
      </div>
    </>
  );
}
