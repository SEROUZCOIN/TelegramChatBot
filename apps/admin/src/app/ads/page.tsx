'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';

interface Placement {
  id: string;
  slot: string;
  network: string;
  unitIdIos: string;
  unitIdAndroid: string;
  isEnabled: boolean;
  minIntervalSec: number;
  hideForPlans: string[];
}

export default function AdsPage() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-ads'],
    queryFn: () => api<Placement[]>('/admin/ads'),
  });

  const save = useMutation({
    mutationFn: (body: Partial<Placement>) =>
      api('/admin/ads', { method: 'PUT', body: JSON.stringify(body) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-ads'] }),
  });

  if (isLoading) return <div className="empty">Loading…</div>;

  return (
    <>
      <h2>Ads</h2>
      <p className="lede">Passive revenue from free and lower tiers.</p>

      <div className="notice">
        Suppression is enforced on the server: a plan listed under{' '}
        <strong>Hidden for</strong> never receives the ad unit ids at all, so a subscriber who paid
        not to see ads cannot be shown them by a stale or modified build.
      </div>

      <div className="grid cols-2">
        {(data ?? []).map((p) => (
          <div className="card" key={p.id}>
            <h3>
              {p.slot} <span className="badge">{p.network}</span>
            </h3>

            <div className="field">
              <label htmlFor={`ios-${p.slot}`}>iOS ad unit id</label>
              <input
                id={`ios-${p.slot}`}
                className="mono"
                defaultValue={p.unitIdIos}
                placeholder="ca-app-pub-…"
                onBlur={(e) =>
                  e.target.value !== p.unitIdIos &&
                  save.mutate({ ...p, unitIdIos: e.target.value })
                }
              />
            </div>

            <div className="field">
              <label htmlFor={`android-${p.slot}`}>Android ad unit id</label>
              <input
                id={`android-${p.slot}`}
                className="mono"
                defaultValue={p.unitIdAndroid}
                placeholder="ca-app-pub-…"
                onBlur={(e) =>
                  e.target.value !== p.unitIdAndroid &&
                  save.mutate({ ...p, unitIdAndroid: e.target.value })
                }
              />
            </div>

            <div className="row">
              <div className="field">
                <label htmlFor={`int-${p.slot}`}>Min seconds between impressions</label>
                <input
                  id={`int-${p.slot}`}
                  type="number"
                  defaultValue={p.minIntervalSec}
                  onBlur={(e) =>
                    save.mutate({ ...p, minIntervalSec: Number(e.target.value) || 0 })
                  }
                />
              </div>
              <div className="field">
                <label>Hidden for</label>
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', paddingTop: 6 }}>
                  {(['SIGNALS', 'NORMAL', 'PRO', 'ULTRA'] as const).map((code) => {
                    const on = p.hideForPlans.includes(code);
                    return (
                      <button
                        key={code}
                        className={on ? 'sm' : 'ghost sm'}
                        onClick={() =>
                          save.mutate({
                            ...p,
                            hideForPlans: on
                              ? p.hideForPlans.filter((c) => c !== code)
                              : [...p.hideForPlans, code],
                          })
                        }
                      >
                        {code}
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>

            <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <input
                type="checkbox"
                style={{ width: 'auto' }}
                checked={p.isEnabled}
                onChange={(e) => save.mutate({ ...p, isEnabled: e.target.checked })}
              />
              Enabled
            </label>
            {!p.unitIdIos && !p.unitIdAndroid && p.isEnabled && (
              <div className="badge warn" style={{ marginTop: 8 }}>
                Enabled with no unit ids — nothing will render
              </div>
            )}
          </div>
        ))}
      </div>
    </>
  );
}
