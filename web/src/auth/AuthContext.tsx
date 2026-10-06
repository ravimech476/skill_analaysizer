import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { authApi } from '../api/endpoints';
import { setSessionExpiredHandler, tokenStore } from '../api/client';
import type { SessionUser, TokenResponse } from '../api/types';

interface AuthState {
  user: SessionUser | null;
  loading: boolean;
  /** true if the user has ANY of the permission slugs (admin always true) */
  can: (...perms: string[]) => boolean;
  hasRole: (...roles: string[]) => boolean;
  startSession: (t: TokenResponse) => void;
  logout: () => Promise<void>;
  reload: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<SessionUser | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    if (!tokenStore.access && !tokenStore.refresh) {
      setUser(null);
      return;
    }
    try {
      setUser(await authApi.me());
    } catch {
      tokenStore.clear();
      setUser(null);
    }
  }, []);

  useEffect(() => {
    setSessionExpiredHandler(() => setUser(null));
    reload().finally(() => setLoading(false));
  }, [reload]);

  const startSession = useCallback((t: TokenResponse) => {
    tokenStore.save(t);
    setUser(t.user);
  }, []);

  const logout = useCallback(async () => {
    const refresh = tokenStore.refresh;
    tokenStore.clear();
    setUser(null);
    if (refresh) await authApi.logout(refresh).catch(() => undefined);
  }, []);

  const value = useMemo<AuthState>(() => {
    const isAdmin = !!user?.roles.includes('admin');
    return {
      user,
      loading,
      can: (...perms) => isAdmin || perms.some((p) => user?.permissions.includes(p)),
      hasRole: (...roles) => roles.some((r) => user?.roles.includes(r)),
      startSession,
      logout,
      reload,
    };
  }, [user, loading, startSession, logout, reload]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
