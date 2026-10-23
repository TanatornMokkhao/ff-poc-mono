import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadSettings, missingKeys, requiredKeys } from './settings.js';

const fakeClient = (pages) => ({ send: async () => pages.shift() });

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
  const names = requiredKeys((await import('node:fs')).readFileSync(new URL('./.env.example', import.meta.url), 'utf8'));
  const params = names.map((n) => ({ Name: `/x/staging/be/${n}`, Value: `v-${n}` }));
  const pages = [{ Parameters: params.slice(0, 4), NextToken: 't' }, { Parameters: params.slice(4) }];
  assert.deepEqual(await loadSettings({ env, client: fakeClient(pages) }), { loaded: names.length });
  assert.equal(env[names.at(-1)], `v-${names.at(-1)}`);
});

test('a key missing from the store stops the server', async () => {
  const env = { SSM_PATH: '/x/staging/be/' };
  await assert.rejects(loadSettings({ env, client: fakeClient([{ Parameters: [{ Name: '/x/staging/be/APP_ENV', Value: 'staging' }] }]) }), /No value under \/x\/staging\/be\/ for: .*DB_PASSWORD/);
});
