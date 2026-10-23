import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { notes } from './notes.js';

/** @typedef {import('../../types.js').Request} Request */

/**
 * A request that sends its body (if any) once the handler listens.
 * @param {string} method
 * @param {string[]} [chunks]
 * @returns {Request}
 */
function request(method, chunks = []) {
  const req = Object.assign(new EventEmitter(), { method });
  setImmediate(() => {
    for (const c of chunks) req.emit('data', Buffer.from(c));
    req.emit('end');
  });
  return /** @type {Request} */ (/** @type {unknown} */ (req));
}

/**
 * Runs the handler with a fake database; returns the answer and the queries it made.
 * @param {Request} req
 * @param {(sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }>} [query]
 */
async function answer(req, query = async () => ({ rows: [] })) {
  /** @type {{ sql: string, params?: unknown[] }[]} */
  const calls = [];
  /** @type {{ status: number, body: unknown }} */
  let out = { status: 0, body: undefined };
  const saved = process.env.DATABASE_URL;
  process.env.DATABASE_URL = 'postgres://fake';
  try {
    await notes(req, (status, body) => { out = { status, body }; }, async (sql, params) => { calls.push({ sql, params }); return query(sql, params); });
  } finally {
    if (saved === undefined) delete process.env.DATABASE_URL; else process.env.DATABASE_URL = saved;
  }
  return { ...out, calls };
}

test('without DATABASE_URL, /notes answers 503 for any method', async (t) => {
  if (process.env.DATABASE_URL) return t.skip('a database is configured');
  for (const method of ['GET', 'POST']) {
    /** @type {unknown[]} */
    let got = [];
    await notes(request(method), (s, b) => { got = [s, b]; });
    assert.deepEqual(got, [503, { error: 'no database configured' }], method);
  }
});

test('GET lists the 20 newest notes', async () => {
  const rows = [{ id: 2, body: 'b' }, { id: 1, body: 'a' }];
  const r = await answer(request('GET'), async () => ({ rows }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, rows);
  assert.equal(r.calls.length, 1);
  assert.match(r.calls[0].sql, /ORDER BY id DESC LIMIT 20/);
});

test('POST adds a note from a JSON body sent in pieces', async () => {
  const saved = { id: 3, body: 'hello', author: 'ci' };
  const r = await answer(request('POST', ['{"body":"hel', 'lo","author":"ci"}']), async () => ({ rows: [saved] }));
  assert.equal(r.status, 201);
  assert.deepEqual(r.body, saved);
  assert.match(r.calls[0].sql, /^INSERT INTO notes/);
  assert.deepEqual(r.calls[0].params, ['hello', 'ci']);
});

test('POST without an author stores null', async () => {
  const r = await answer(request('POST', ['{"body":"x"}']), async () => ({ rows: [{}] }));
  assert.deepEqual(r.calls[0].params, ['x', null]);
});

test('POST refuses a body that is not JSON, and one without a text body', async () => {
  assert.deepEqual((await answer(request('POST', ['not json']))).body, { error: 'body is not JSON' });
  assert.equal((await answer(request('POST', ['not json']))).status, 400);
  for (const raw of ['{}', '{"body":""}', '{"body":5}', '']) {
    const r = await answer(request('POST', raw ? [raw] : []));
    assert.deepEqual([r.status, r.body, r.calls.length], [400, { error: 'body is required' }, 0], raw);
  }
});

test('a database failure answers 500 with its message', async () => {
  const r = await answer(request('GET'), async () => { throw new Error('connection refused'); });
  assert.deepEqual([r.status, r.body], [500, { error: 'connection refused' }]);
});

test('other methods answer 405', async () => {
  const r = await answer(request('DELETE'));
  assert.deepEqual([r.status, r.body, r.calls.length], [405, { error: 'GET or POST' }, 0]);
});
