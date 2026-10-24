import { describe, expect, test } from 'vitest';
import { isProd, loadConfig } from './config';

const answer = (status: number, body?: unknown) =>
  (async () => new Response(body === undefined ? null : JSON.stringify(body), { status })) as unknown as typeof fetch;

describe('loadConfig', () => {
  test('config.json overrides the defaults', async () => {
    const c = await loadConfig('/x/', answer(200, { env: 'staging', flags: { welcomeBanner: true }, versions: { be: '1.0.0', fe: '1.0.0' } }));
    expect(c).toEqual({ env: 'staging', apiBaseUrl: '', flags: { welcomeBanner: true }, versions: { be: '1.0.0', fe: '1.0.0' } });
  });

  test('reads it next to the page, never from a cache', async () => {
    let seen: [string, RequestInit | undefined] | undefined;
    const spy = (async (url: string, init?: RequestInit) => { seen = [url, init]; return new Response('{}'); }) as unknown as typeof fetch;
    await loadConfig('/staging/', spy);
    expect(seen).toEqual(['/staging/config.json', { cache: 'no-store' }]);
  });

  test('a missing or broken config.json keeps the defaults', async () => {
    const failing = (async () => { throw new Error('offline'); }) as unknown as typeof fetch;
    for (const f of [answer(404), answer(200, undefined), failing]) {
      expect((await loadConfig('/', f)).flags).toEqual({});
    }
  });
});

test('isProd is true only for prod', () => {
  expect(isProd('prod')).toBe(true);
  expect(isProd('staging')).toBe(false);
  expect(isProd('')).toBe(false);
});
