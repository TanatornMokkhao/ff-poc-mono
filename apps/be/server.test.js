import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { handle } from './server.js';

function get(server, path) {
  return new Promise((resolve, reject) => {
    const { port } = server.address();
    http.get({ port, path }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(body) }));
    }).on('error', reject);
  });
}

test('health and version answer', async () => {
  const server = http.createServer(handle).listen(0);
  try {
    assert.deepEqual((await get(server, '/health')).body, { ok: true });
    const v = (await get(server, '/version')).body;
    assert.equal(v.service, 'be');
    assert.equal(v.commit, process.env.GIT_SHA || 'unknown');
    const info = (await get(server, '/info')).body;
    assert.equal(info.service, 'be');
    assert.equal(typeof info.uptimeSeconds, 'number');
    assert.equal(info.env, 'local');
    assert.equal(info.dbPasswordSet, false);
    assert.equal(JSON.stringify(info).includes('password'), false, 'no secret values in /info');
    assert.deepEqual(await get(server, '/nope'), { status: 404, body: { error: 'not found', path: '/nope' } });
    if (!process.env.DATABASE_URL) assert.equal((await get(server, '/notes')).status, 503);
  } finally {
    server.close();
  }
});
