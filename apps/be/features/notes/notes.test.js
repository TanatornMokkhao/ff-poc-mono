import { test } from 'node:test';
import assert from 'node:assert/strict';
import { notes } from './notes.js';

test('without DATABASE_URL, /notes answers 503 for any method', async (t) => {
  if (process.env.DATABASE_URL) return t.skip('a database is configured');
  for (const method of ['GET', 'POST']) {
    let status;
    let body;
    // Only the method is read before the database check.
    const req = /** @type {import('../../types.js').Request} */ (/** @type {unknown} */ ({ method }));
    await notes(req, (s, b) => { status = s; body = b; });
    assert.equal(status, 503, method);
    assert.deepEqual(body, { error: 'no database configured' });
  }
});
