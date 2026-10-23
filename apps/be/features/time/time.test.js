import { test } from 'node:test';
import assert from 'node:assert/strict';
import { time } from './time.js';

test('/time answers the current time in UTC', () => {
  let status;
  /** @type {{ now: string }} */
  let body = { now: '' };
  const before = Date.now();
  time((s, b) => { status = s; body = /** @type {{ now: string }} */ (b); });
  assert.equal(status, 200);
  assert.match(body.now, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  assert.ok(Math.abs(Date.parse(body.now) - before) < 5000, 'the answer is the time now');
});
