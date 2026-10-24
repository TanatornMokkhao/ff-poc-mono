import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dbConfig, RDS_CA } from './db.js';

/** @type {string[]} */
let read = [];
const readCa = (/** @type {string} */ path) => (read.push(path), `CA from ${path}`);
const parts = { RUNTIME: 'ecs', DB_HOST: 'db.internal', DB_NAME: 'app', DB_USERNAME: 'app', DB_PASSWORD: 'p@ss/word' };

test('DATABASE_URL is used as given, and wins over the parts', () => {
  read = [];
  assert.deepEqual(dbConfig({ ...parts, DATABASE_URL: 'postgres://u:p@h/d' }, readCa), { connectionString: 'postgres://u:p@h/d' });
  assert.deepEqual(read, [], 'no certificate is read for a plain URL');
});

test('on the platform, the parts become a TLS connection checked against the RDS bundle', () => {
  read = [];
  assert.deepEqual(dbConfig(parts, readCa), {
    host: 'db.internal', port: 5432, database: 'app', user: 'app', password: 'p@ss/word', ssl: { ca: `CA from ${RDS_CA}` },
  });
  assert.equal(RDS_CA, '/etc/ssl/certs/rds-global-bundle.pem');
});

test('DB_PORT and DB_SSL_CA override the defaults', () => {
  const c = dbConfig({ ...parts, DB_PORT: '6543', DB_SSL_CA: '/tmp/ca.pem' }, readCa);
  assert.equal(c?.port, 6543);
  assert.deepEqual(c?.ssl, { ca: 'CA from /tmp/ca.pem' });
});

test('no database without RUNTIME, a host or a password', () => {
  read = [];
  assert.equal(dbConfig({ ...parts, RUNTIME: undefined }, readCa), null, 'the old deploy keeps its placeholders unused');
  assert.equal(dbConfig({ ...parts, DB_HOST: '' }, readCa), null);
  assert.equal(dbConfig({ ...parts, DB_PASSWORD: undefined }, readCa), null);
  assert.equal(dbConfig({}, readCa), null);
  assert.deepEqual(read, []);
});

test('reads the real bundle file by default', () => {
  assert.throws(() => dbConfig({ ...parts, DB_SSL_CA: '/no/such/ca.pem' }), /ENOENT/);
});
