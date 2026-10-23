// Every rule in scripts/check-migrations.mjs, each with the exact problem it must report and the
// near misses it must let through. checkAll runs against a throwaway git repo with a release tag.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { checkAll, checkFile } from './scripts/check-migrations.mjs';

const expand = (/** @type {string} */ sql) => checkFile('0003_x.sql', `-- kind: expand\n${sql}`);

test('each breaking statement in an expand migration is reported with what it does', () => {
  const cases = [
    ['ALTER TABLE t DROP COLUMN c;', 'drops something'],
    ['DROP TABLE t;', 'drops something'],
    ['DROP VIEW v;', 'drops something'],
    ['DROP SCHEMA s;', 'drops something'],
    ['DROP TYPE k;', 'drops something'],
    ['ALTER TABLE t RENAME COLUMN a TO b;', 'renames something'],
    ['ALTER TABLE t ALTER COLUMN c TYPE TEXT;', 'changes a column type'],
    ['ALTER TABLE t ALTER COLUMN c SET DATA TYPE TEXT;', 'changes a column type'],
    ['ALTER TABLE t ALTER COLUMN c SET NOT NULL;', 'makes a column NOT NULL (old code may insert without it)'],
    ['ALTER TABLE t ADD COLUMN c INT NOT NULL;', 'adds a NOT NULL column without a DEFAULT'],
    ['TRUNCATE t;', 'empties a table'],
    ['DELETE FROM t;', 'deletes rows (data changes go in a command, not a migration)'],
  ];
  for (const [sql, what] of cases) {
    assert.deepEqual(expand(sql), [`0003_x.sql: an expand migration ${what}; that is a contract`], sql);
    // Any run of spaces or a line break between the words: the same statement, the same finding.
    const spread = sql.replace(/ /g, '  \n ');
    assert.deepEqual(expand(spread), [`0003_x.sql: an expand migration ${what}; that is a contract`], spread);
  }
});

test('the rules ignore case and spacing', () => {
  assert.equal(expand('alter table t   drop\n  column c;').length, 1);
  assert.equal(expand('delete   from t;').length, 1);
});

test('near misses are not breaking', () => {
  for (const sql of [
    'ALTER TABLE t ADD COLUMN c INT NOT NULL DEFAULT 0;',
    'ALTER TABLE t ADD COLUMN c TEXT;',
    'ALTER TABLE t ADD COLUMN c TEXT; ALTER TABLE u ADD COLUMN d INT NOT NULL DEFAULT 1;',
    'ALTER TABLE t ALTER COLUMN c SET DEFAULT 0;',
    'ALTER TABLE t ALTER COLUMN c DROP NOT NULL;',
    'CREATE TABLE renamed_things (id INT);',
    'CREATE INDEX ON t (c);',
    "INSERT INTO log VALUES ('DELETE FROMAGE');",
  ]) {
    assert.deepEqual(expand(sql), [], sql);
  }
});

test('a NOT NULL column is judged per statement', () => {
  assert.equal(expand('ALTER TABLE t ADD COLUMN a INT; ALTER TABLE t ADD COLUMN b INT NOT NULL;').length, 1);
  assert.deepEqual(expand('ALTER TABLE t ADD COLUMN a INT NOT NULL DEFAULT 1; ALTER TABLE t ADD COLUMN b TEXT;'), []);
  assert.deepEqual(expand('ALTER TABLE t ADD COLUMN a TEXT; UPDATE x SET y = 1 WHERE z IS NOT NULL;'), []);
});

// Both were wrong before 2026-10-24, found by mutation testing: the DEFAULT was looked for only
// after NOT NULL, and the statement had to end with a semicolon.
test('a DEFAULT before NOT NULL is fine; a last statement without a semicolon still counts', () => {
  assert.deepEqual(expand('ALTER TABLE t ADD COLUMN c INT DEFAULT 0 NOT NULL;'), []);
  assert.equal(expand('ALTER TABLE t ADD COLUMN c INT NOT NULL').length, 1);
  assert.equal(expand('ALTER TABLE t ADD COLUMN c INT NOT NULL CHECK (c > 0);').length, 1);
});

test('removes-use-from takes any X.Y.Z on its own line, with any spacing', () => {
  const ok = (/** @type {string} */ line) => checkFile('0004_x.sql', `-- kind: contract\n${line}\nDROP TABLE t;`);
  assert.deepEqual(ok('-- removes-use-from: 10.20.30'), []);
  assert.deepEqual(ok('--   removes-use-from:   1.2.0   '), []);
  assert.deepEqual(ok('--removes-use-from:1.2.0'), []);
  assert.equal(ok('-- removes-use-from: 1.2.0 or later').length, 1);
  assert.equal(ok('SELECT 1; -- removes-use-from: 1.2.0').length, 1);
});

test('breaking words in line and block comments do not count', () => {
  assert.deepEqual(expand('-- DROP TABLE t\n/* TRUNCATE t;\n DELETE FROM t; */\nCREATE TABLE x (id INT);'), []);
});

test('several breaking statements are each reported', () => {
  assert.equal(expand('DROP TABLE a; TRUNCATE b;').length, 2);
});

test('the kind must be its own line, expand or contract', () => {
  const noKind = '0003_x.sql: first lines must say "-- kind: expand" or "-- kind: contract"';
  assert.deepEqual(checkFile('0003_x.sql', 'CREATE TABLE y (id INT);'), [noKind]);
  assert.deepEqual(checkFile('0003_x.sql', '-- kind: expandable\nCREATE TABLE y (id INT);'), [noKind]);
  assert.deepEqual(checkFile('0003_x.sql', 'SELECT 1; -- kind: expand\n'), [noKind]);
  assert.deepEqual(checkFile('0003_x.sql', '--kind:expand\nCREATE TABLE y (id INT);'), []);
});

test('a contract needs removes-use-from with a full version, and may break', () => {
  const need = '0004_x.sql: a contract must say "-- removes-use-from: X.Y.Z", the first release that no longer uses what it removes';
  assert.deepEqual(checkFile('0004_x.sql', '-- kind: contract\nDROP TABLE t;'), [need]);
  assert.deepEqual(checkFile('0004_x.sql', '-- kind: contract\n-- removes-use-from: 1.2\nDROP TABLE t;'), [need]);
  assert.deepEqual(checkFile('0004_x.sql', '-- kind: contract\n-- removes-use-from: 1.2.0\nDROP TABLE t; TRUNCATE u;'), []);
});

test('file names are NNNN_lower_snake.sql, and a bad name is reported with the other problems', () => {
  const bad = (/** @type {string} */ n) => `${n}: name must be NNNN_lower_snake.sql`;
  assert.deepEqual(checkFile('5_x.sql', '-- kind: expand\nSELECT 1;'), [bad('5_x.sql')]);
  assert.deepEqual(checkFile('0005_Upper.sql', '-- kind: expand\nSELECT 1;'), [bad('0005_Upper.sql')]);
  assert.deepEqual(checkFile('0005_x.SQL', '-- kind: expand\nSELECT 1;'), [bad('0005_x.SQL')]);
  assert.deepEqual(checkFile('x0005_a.sql', '-- kind: expand\nSELECT 1;'), [bad('x0005_a.sql')]);
  assert.deepEqual(checkFile('0005_a.sql.bak', '-- kind: expand\nSELECT 1;'), [bad('0005_a.sql.bak')]);
  assert.deepEqual(checkFile('0005_x.sql', '-- kind: expand\nSELECT 1;'), []);
  assert.equal(checkFile('5_x.sql', '-- kind: expand\nDROP TABLE t;').length, 2);
});

// A repo with migrations/0001 and 0002 released as tag v1, then the working tree for the case.
function repo() {
  const root = mkdtempSync(join(tmpdir(), 'mig-'));
  const git = (/** @type {string[]} */ ...a) => execFileSync('git', a, { cwd: root, stdio: ['ignore', 'pipe', 'ignore'] });
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 't@t');
  git('config', 'user.name', 't');
  mkdirSync(join(root, 'migrations'));
  const put = (/** @type {string} */ f, /** @type {string} */ sql) => writeFileSync(join(root, 'migrations', f), sql);
  put('0001_a.sql', '-- kind: expand\nCREATE TABLE a (id INT);\n');
  put('0002_b.sql', '-- kind: expand\nCREATE TABLE b (id INT);\n');
  git('add', '-A');
  git('commit', '-qm', 'v1');
  git('tag', 'v1');
  const dir = pathToFileURL(join(root, 'migrations') + '/');
  return { root, dir, put, drop: (/** @type {string} */ f) => unlinkSync(join(root, 'migrations', f)), done: () => rmSync(root, { recursive: true, force: true }) };
}

test('checkAll: released files unchanged and a new file after them pass', () => {
  const r = repo();
  try {
    r.put('0003_c.sql', '-- kind: expand\nCREATE TABLE c (id INT);\n');
    r.put('notes.txt', 'not a migration');
    assert.deepEqual(checkAll(r.dir, 'v1', r.root), []);
  } finally { r.done(); }
});

test('checkAll: a released file that changed is reported', () => {
  const r = repo();
  try {
    r.put('0002_b.sql', '-- kind: expand\nCREATE TABLE b (id BIGINT);\n');
    assert.deepEqual(checkAll(r.dir, 'v1', r.root), ['0002_b.sql was released in v1 and has changed; add a new migration instead']);
  } finally { r.done(); }
});

test('checkAll: a released file that is gone is reported', () => {
  const r = repo();
  try {
    r.drop('0002_b.sql');
    assert.deepEqual(checkAll(r.dir, 'v1', r.root), ['0002_b.sql was released in v1 and is gone; released migrations never change']);
  } finally { r.done(); }
});

test('checkAll: a new file numbered before the last released one is reported', () => {
  const r = repo();
  try {
    r.put('0001_late.sql', '-- kind: expand\nCREATE TABLE late (id INT);\n');
    assert.deepEqual(checkAll(r.dir, 'v1', r.root), [
      'two migrations are numbered 0001',
      '0001_late.sql sorts before 0002_b.sql, already released; number it after',
    ]);
  } finally { r.done(); }
});

test('checkAll: two files with one number are reported even without a release', () => {
  const r = repo();
  try {
    r.put('0003_c.sql', '-- kind: expand\nSELECT 1;\n');
    r.put('0003_d.sql', '-- kind: expand\nSELECT 1;\n');
    assert.deepEqual(checkAll(r.dir, undefined, r.root), ['two migrations are numbered 0003']);
  } finally { r.done(); }
});

test('checkAll: a release without migrations, or an unknown ref, compares with nothing', () => {
  const r = repo();
  try {
    r.put('0003_c.sql', '-- kind: expand\nSELECT 1;\n');
    assert.deepEqual(checkAll(r.dir, 'no-such-ref', r.root), []);
  } finally { r.done(); }
});

test('checkAll: "number it after" compares with the newest released file', () => {
  const r = repo();
  try {
    r.put('0003_c.sql', '-- kind: expand\nCREATE TABLE c (id INT);\n');
    execFileSync('git', ['add', '-A'], { cwd: r.root });
    execFileSync('git', ['commit', '-qm', 'v2'], { cwd: r.root });
    execFileSync('git', ['tag', 'v2'], { cwd: r.root });
    r.put('0002_z.sql', '-- kind: expand\nCREATE TABLE z (id INT);\n');
    assert.deepEqual(checkAll(r.dir, 'v2', r.root), [
      'two migrations are numbered 0002',
      '0002_z.sql sorts before 0003_c.sql, already released; number it after',
    ]);
  } finally { r.done(); }
});

test('run as a script it checks apps/be/migrations and says so', () => {
  const out = execFileSync('node', ['scripts/check-migrations.mjs'], {
    cwd: new URL('.', import.meta.url),
    encoding: 'utf8',
    env: { ...process.env, BASE_REF: '' },
  });
  assert.equal(out.trim(), 'migrations follow expand / contract');
});

test('checkAll: file problems come through', () => {
  const r = repo();
  try {
    r.put('0003_c.sql', '-- kind: expand\nDROP TABLE a;\n');
    assert.deepEqual(checkAll(r.dir, 'v1', r.root), ['0003_c.sql: an expand migration drops something; that is a contract']);
  } finally { r.done(); }
});
