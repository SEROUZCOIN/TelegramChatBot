import { useQuery, useQueryClient } from '@tanstack/react-query';
import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import type { Entitlements } from '@tsp/shared';
import { api, tokens } from './api';

export interface Profile {
  id: string;
  email: string;
  displayName: string;
  role: string;
  telegramUsername: string | null;
  telegramLinkCode: string | null;
  riskDisclaimerAcceptedAt: string | null;
  riskDisclaimerVersion: string | null;
}

interface SessionValue {
  status: 'loading' | 'anon' | 'needs-disclaimer' | 'ready';
  profile: Profile | null;
  entitlements: Entitlements | null;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionValue | null>(null);

/**
 * Session and gating.
 *
 * The disclaimer is a hard gate ahead of the app rather than a dismissible
 * banner: acceptance is recorded server-side with the version accepted, and
 * bumping RISK_DISCLAIMER_VERSION on the API re-gates everyone. Both stores
 * scrutinise trading apps, and this is the artifact that shows every user saw
 * the risk warning.
 */
export function SessionProvider({ children }: { children: React.ReactNode }) {
  const qc = useQueryClient();
  const [hasToken, setHasToken] = useState<boolean | null>(null);

  useEffect(() => {
    void tokens.access().then((t) => setHasToken(Boolean(t)));
  }, []);

  const profileQuery = useQuery({
    queryKey: ['me'],
    queryFn: () => api<Profile>('/me'),
    enabled: hasToken === true,
    retry: false,
  });

  const entitlementsQuery = useQuery({
    queryKey: ['entitlements'],
    queryFn: () => api<Entitlements>('/me/entitlements'),
    enabled: hasToken === true && profileQuery.isSuccess,
    // Re-checked on every foreground so a lapsed plan locks up promptly.
    refetchOnWindowFocus: true,
    staleTime: 30_000,
  });

  const refresh = useCallback(async () => {
    setHasToken(Boolean(await tokens.access()));
    await qc.invalidateQueries();
  }, [qc]);

  const signOut = useCallback(async () => {
    await tokens.clear();
    setHasToken(false);
    qc.clear();
  }, [qc]);

  const status: SessionValue['status'] =
    hasToken === null || (hasToken && profileQuery.isLoading)
      ? 'loading'
      : !hasToken || profileQuery.isError
        ? 'anon'
        : !profileQuery.data?.riskDisclaimerAcceptedAt
          ? 'needs-disclaimer'
          : 'ready';

  return (
    <SessionContext.Provider
      value={{
        status,
        profile: profileQuery.data ?? null,
        entitlements: entitlementsQuery.data ?? null,
        refresh,
        signOut,
      }}
    >
      {children}
    </SessionContext.Provider>
  );
}

export function useSession(): SessionValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession must be used inside SessionProvider');
  return ctx;
}
