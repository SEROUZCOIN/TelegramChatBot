import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

const API_URL =
  process.env.EXPO_PUBLIC_API_URL ??
  (Constants.expoConfig?.extra as { apiUrl?: string } | undefined)?.apiUrl ??
  'http://localhost:3000/api';

const ACCESS_KEY = 'tsp.access';
const REFRESH_KEY = 'tsp.refresh';

/**
 * Tokens go to the Keychain / Keystore via SecureStore on device.
 *
 * SecureStore has no web implementation, so the web target falls back to
 * AsyncStorage — acceptable there because the web build is a preview surface,
 * not the shipped product.
 */
const store = {
  async get(key: string): Promise<string | null> {
    if (Platform.OS === 'web') return AsyncStorage.getItem(key);
    return SecureStore.getItemAsync(key);
  },
  async set(key: string, value: string | null): Promise<void> {
    if (value === null) {
      if (Platform.OS === 'web') return AsyncStorage.removeItem(key);
      return SecureStore.deleteItemAsync(key);
    }
    if (Platform.OS === 'web') return AsyncStorage.setItem(key, value);
    return SecureStore.setItemAsync(key, value);
  },
};

export const tokens = {
  access: () => store.get(ACCESS_KEY),
  refresh: () => store.get(REFRESH_KEY),
  async save(access: string, refresh: string): Promise<void> {
    await Promise.all([store.set(ACCESS_KEY, access), store.set(REFRESH_KEY, refresh)]);
  },
  async clear(): Promise<void> {
    await Promise.all([store.set(ACCESS_KEY, null), store.set(REFRESH_KEY, null)]);
  },
};

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
  }
}

let refreshing: Promise<boolean> | null = null;

/**
 * Refresh the access token, coalescing concurrent attempts.
 *
 * Several screens fetch at once on app resume; without this, an expired token
 * would fire one refresh per screen and the losers would be handed tokens that
 * the winner has already rotated away.
 */
async function refreshSession(): Promise<boolean> {
  if (refreshing) return refreshing;

  refreshing = (async () => {
    const refreshToken = await tokens.refresh();
    if (!refreshToken) return false;

    try {
      const res = await fetch(`${API_URL}/auth/refresh`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
      });
      if (!res.ok) {
        await tokens.clear();
        return false;
      }
      const data = (await res.json()) as { accessToken: string; refreshToken: string };
      await tokens.save(data.accessToken, data.refreshToken);
      return true;
    } catch {
      return false;
    } finally {
      refreshing = null;
    }
  })();

  return refreshing;
}

export async function api<T>(
  path: string,
  options: RequestInit & { auth?: boolean; _retried?: boolean } = {},
): Promise<T> {
  const { auth = true, _retried = false, headers, ...rest } = options;
  const token = auth ? await tokens.access() : null;

  const res = await fetch(`${API_URL}${path}`, {
    ...rest,
    headers: {
      'content-type': 'application/json',
      'x-client-platform': Platform.OS,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
  });

  // One transparent retry after a refresh, so a token expiring mid-session is
  // invisible rather than bouncing the user to the login screen.
  if (res.status === 401 && auth && !_retried) {
    if (await refreshSession()) {
      return api<T>(path, { ...options, _retried: true });
    }
  }

  const text = await res.text();
  const body = text ? JSON.parse(text) : null;

  if (!res.ok) {
    const message = (body as { message?: string })?.message ?? `Request failed (${res.status})`;
    throw new ApiError(message, res.status, body);
  }

  return body as T;
}

export async function login(email: string, password: string): Promise<void> {
  const data = await api<{ accessToken: string; refreshToken: string }>('/auth/login', {
    method: 'POST',
    auth: false,
    body: JSON.stringify({ email, password }),
  });
  await tokens.save(data.accessToken, data.refreshToken);
}

export async function register(input: {
  email: string;
  password: string;
  displayName: string;
}): Promise<void> {
  const data = await api<{ accessToken: string; refreshToken: string }>('/auth/register', {
    method: 'POST',
    auth: false,
    body: JSON.stringify({ ...input, locale: 'en' }),
  });
  await tokens.save(data.accessToken, data.refreshToken);
}

export { API_URL };
