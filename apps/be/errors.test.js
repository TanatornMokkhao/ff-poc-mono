import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messageOf } from './errors.js';

test('messageOf gives an Error its message and anything else as text', () => {
  assert.equal(messageOf(new Error('boom')), 'boom');
  assert.equal(messageOf(new TypeError('bad type')), 'bad type');
  assert.equal(messageOf('plain text'), 'plain text');
  assert.equal(messageOf(42), '42');
  assert.equal(messageOf(undefined), 'undefined');
});
