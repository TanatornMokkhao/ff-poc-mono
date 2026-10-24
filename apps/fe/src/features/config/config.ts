import { ref } from 'vue';

export interface RuntimeConfig {
  env: string;
  apiBaseUrl: string;
  flags: Record<string, boolean>;
  versions?: { be: string; fe: string };
  runtime?: Record<string, string>;
}

// env and flags arrive in config.json, baked per stage at build time; the deploy adds the versions.
export function defaultConfig(env = import.meta.env.VITE_API_ENV || 'local'): RuntimeConfig {
  return { env, apiBaseUrl: '', flags: {} };
}

// Reads <base>config.json over the build-time defaults; keeps the defaults when it is missing.
export async function loadConfig(base: string, fetchFn: typeof fetch = fetch): Promise<RuntimeConfig> {
  const config = defaultConfig();
  try {
    const res = await fetchFn(`${base}config.json`, { cache: 'no-store' });
    if (res.ok) return { ...config, ...(await res.json()) };
  } catch {
    // Missing or unreadable: the defaults stand.
  }
  return config;
}

export function useConfig() {
  const config = ref<RuntimeConfig>(defaultConfig());
  const load = async () => { config.value = await loadConfig(import.meta.env.BASE_URL); };
  return { config, load };
}

// Production builds talk to the production API.
export const isProd = (env: string): boolean => env === 'prod';
