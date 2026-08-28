import type { Metadata } from 'next';
import './globals.css';
import { Providers } from './providers';
import { Sidebar } from '@/components/sidebar';
import { AuthGate } from '@/components/auth-gate';

export const metadata: Metadata = {
  title: 'Signals Admin',
  description: 'Control panel for the trading signals and academy platform',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <AuthGate>
            <div className="layout">
              <Sidebar />
              <main className="main">{children}</main>
            </div>
          </AuthGate>
        </Providers>
      </body>
    </html>
  );
}
