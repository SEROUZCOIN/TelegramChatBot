'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { setToken } from '@/lib/api';

const GROUPS: Array<{ label: string; items: Array<{ href: string; label: string }> }> = [
  {
    label: 'Overview',
    items: [{ href: '/', label: 'Dashboard' }],
  },
  {
    label: 'Trading',
    items: [
      { href: '/signals', label: 'Signals' },
      { href: '/signals/new', label: 'New signal' },
    ],
  },
  {
    label: 'Academy',
    items: [
      { href: '/courses', label: 'Courses' },
      { href: '/coaching', label: 'Coaching' },
    ],
  },
  {
    label: 'Revenue',
    items: [
      { href: '/payments', label: 'Payment queue' },
      { href: '/plans', label: 'Plans & pricing' },
      { href: '/users', label: 'Users' },
    ],
  },
  {
    label: 'Growth',
    items: [
      { href: '/links', label: 'Links' },
      { href: '/ads', label: 'Ads' },
      { href: '/broadcast', label: 'Push & Telegram' },
    ],
  },
  {
    label: 'System',
    items: [{ href: '/audit', label: 'Audit log' }],
  },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="sidebar">
      <h1>Signals Admin</h1>
      <p className="sub">Control panel</p>

      {GROUPS.map((group) => (
        <div key={group.label}>
          <div className="group">{group.label}</div>
          <nav>
            {group.items.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className={pathname === item.href ? 'active' : ''}
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>
      ))}

      <div style={{ marginTop: 28, padding: '0 10px' }}>
        <button
          className="ghost sm"
          style={{ width: '100%' }}
          onClick={() => {
            setToken(null);
            window.location.reload();
          }}
        >
          Sign out
        </button>
      </div>
    </aside>
  );
}
