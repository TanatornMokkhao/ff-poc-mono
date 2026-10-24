import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { loadSettings, missingKeys, requiredKeys } from './settings.js';

const fakeClient = (/** @type {object[]} */ pages) => ({ send: async () => pages.shift() });

test('requiredKeys reads key names and skips comments', () => {
  assert.deepEqual(requiredKeys('# c\nA=1\n\nB= # secret\nC= # secret optional\n'), ['A', 'B']);
});

test('missingKeys names keys without a value', () => {
  assert.deepEqual(missingKeys(['A', 'B'], { A: 'x', B: '' }), ['B']);
});

test('without SSM_PATH nothing is loaded or checked', async () => {
  assert.deepEqual(await loadSettings({ env: {}, client: fakeClient([]) }), { loaded: 0 });
});

test('loads every page under the path into env', async () => {
  const env = { SSM_PATH: '/x/staging/be/' };
  const names = requiredKeys((await import('node:fs')).readFileSync(new URL('../../.env.example', import.meta.url), 'utf8'));
  const params = names.map((n) => ({ Name: `/x/staging/be/${n}`, Value: `v-${n}` }));
  const pages = [{ Parameters: params.slice(0, 4), NextToken: 't' }, { Parameters: params.slice(4) }];
  assert.deepEqual(await loadSettings({ env, client: fakeClient(pages) }), { loaded: names.length });
  const last = names[names.length - 1];
  assert.equal(env[/** @type {keyof typeof env} */ (last)], `v-${last}`);
});

test('a key missing from the store stops the server', async () => {
  const env = { SSM_PATH: '/x/staging/be/' };
  await assert.rejects(loadSettings({ env, client: fakeClient([{ Parameters: [{ Name: '/x/staging/be/APP_ENV', Value: 'staging' }] }]) }), /No value under \/x\/staging\/be\/ for: .*DB_PASSWORD/);
});

test('a parameter without a name is skipped', async () => {
  /** @type {Record<string, string | undefined>} */
  const env = { SSM_PATH: '/x/staging/be/' };
  const names = requiredKeys((await import('node:fs')).readFileSync(new URL('../../.env.example', import.meta.url), 'utf8'));
  const params = [{ Value: 'orphan' }, ...names.map((n) => ({ Name: `/x/staging/be/${n}`, Value: 'v' }))];
  assert.deepEqual(await loadSettings({ env, client: fakeClient([{ Parameters: params }]) }), { loaded: names.length });
  assert.equal(Object.values(env).includes('orphan'), false);
});

const storeWith = (/** @type {Record<string, string>} */ values) => {
  const names = requiredKeys(fs.readFileSync(new URL('../../.env.example', import.meta.url), 'utf8'));
  return [{ Parameters: names.map((n) => ({ Name: `/x/staging/be/${n}`, Value: values[n] ?? `store-${n}` })) }];
};

test('where the platform runs the be, its values win over the store', async () => {
  /** @type {Record<string, string | undefined>} */
  const env = { SSM_PATH: '/x/staging/be/', RUNTIME: 'ecs', DB_HOST: 'db.internal', REDIS_QUEUE_HOST: '' };
  const { loaded } = await loadSettings({ env, client: fakeClient(storeWith({})) });
  assert.equal(env.DB_HOST, 'db.internal');
  assert.equal(env.REDIS_QUEUE_HOST, 'store-REDIS_QUEUE_HOST', 'an empty platform value does not count');
  assert.equal(env.APP_ENV, 'store-APP_ENV');
  assert.equal(loaded, requiredKeys(fs.readFileSync(new URL('../../.env.example', import.meta.url), 'utf8')).length - 1);
});

test('without RUNTIME the store wins, as before', async () => {
  /** @type {Record<string, string | undefined>} */
  const env = { SSM_PATH: '/x/staging/be/', DB_HOST: 'from-the-shell' };
  await loadSettings({ env, client: fakeClient(storeWith({})) });
  assert.equal(env.DB_HOST, 'store-DB_HOST');
});
