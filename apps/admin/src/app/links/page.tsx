'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';

interface AdminLink {
  id: string;
  label: string;
  url: string;
  icon: string;
  category: string;
  sortOrder: number;
  isActive: boolean;
  clickCount: number;
}

export default function LinksPage() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-links'],
    queryFn: () => api<AdminLink[]>('/admin/links'),
  });

  const create = useMutation({
    mutationFn: (body: Partial<AdminLink>) =>
      api('/admin/links', { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-links'] }),
  });

  const update = useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: Partial<AdminLink> }) =>
      api(`/admin/links/${id}`, { method: 'PUT', body: JSON.stringify(patch) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-links'] }),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api(`/admin/links/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-links'] }),
  });

  function onAdd(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    create.mutate({
      label: String(f.get('label')),
      url: String(f.get('url')),
      icon: String(f.get('icon') || 'link'),
      category: String(f.get('category')),
      sortOrder: Number(f.get('sortOrder') || 0),
    });
    e.currentTarget.reset();
  }

  return (
    <>
      <h2>Links</h2>
      <p className="lede">
        Shown in the app&apos;s profile tab. Taps are counted server-side, so a link&apos;s
        destination can change later without shipping a new build.
      </p>

      <div className="card" style={{ marginBottom: 14 }}>
        <h3>Add a link</h3>
        <form onSubmit={onAdd}>
          <div className="row">
            <div className="field">
              <label htmlFor="label">Label</label>
              <input id="label" name="label" required placeholder="Telegram channel" />
            </div>
            <div className="field">
              <label htmlFor="url">URL</label>
              <input id="url" name="url" type="url" required placeholder="https://t.me/…" />
            </div>
            <div className="field">
              <label htmlFor="category">Category</label>
              <select id="category" name="category" defaultValue="SOCIAL">
                <option>SOCIAL</option>
                <option>CHANNEL</option>
                <option>BROKER</option>
                <option>SUPPORT</option>
                <option>OTHER</option>
              </select>
            </div>
            <div className="field">
              <label htmlFor="icon">Icon</label>
              <input id="icon" name="icon" defaultValue="link" />
            </div>
            <div className="field">
              <label htmlFor="sortOrder">Order</label>
              <input id="sortOrder" name="sortOrder" type="number" defaultValue={0} />
            </div>
          </div>
          <button type="submit" disabled={create.isPending}>
            Add link
          </button>
        </form>
      </div>

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Label</th>
              <th>URL</th>
              <th>Category</th>
              <th className="num">Clicks</th>
              <th>Active</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr>
                <td colSpan={6} className="empty">
                  Loading…
                </td>
              </tr>
            )}
            {(data ?? []).map((l) => (
              <tr key={l.id}>
                <td>{l.label}</td>
                <td className="mono">
                  <a href={l.url} target="_blank" rel="noreferrer">
                    {l.url.length > 44 ? `${l.url.slice(0, 44)}…` : l.url}
                  </a>
                </td>
                <td>
                  <span className="badge">{l.category}</span>
                </td>
                <td className="num mono">{l.clickCount}</td>
                <td>
                  <input
                    type="checkbox"
                    style={{ width: 'auto' }}
                    checked={l.isActive}
                    onChange={(e) => update.mutate({ id: l.id, patch: { isActive: e.target.checked } })}
                  />
                </td>
                <td>
                  <button className="danger sm" onClick={() => remove.mutate(l.id)}>
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
