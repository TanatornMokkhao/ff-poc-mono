import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkFile } from './scripts/check-migrations.mjs';
import { kindOf, migrationFiles } from './migrate.js';

test('the shipped migrations follow the rules', async () => {
  const { readFileSync } = await import('node:fs');
  for (const f of migrationFiles()) {
    assert.deepEqual(checkFile(f, readFileSync(new URL(`./migrations/${f}`, import.meta.url), 'utf8')), [], f);
  }
});

test('an expand migration may only add', () => {
  assert.deepEqual(checkFile('0003_ok.sql', '-- kind: expand\nALTER TABLE notes ADD COLUMN tag TEXT;'), []);
  assert.deepEqual(checkFile('0003_ok.sql', '-- kind: expand\nALTER TABLE notes ADD COLUMN n INT NOT NULL DEFAULT 0;'), []);
  for (const sql of [
    'ALTER TABLE notes DROP COLUMN author;',
    'ALTER TABLE notes RENAME COLUMN body TO text;',
    'ALTER TABLE notes ALTER COLUMN body TYPE VARCHAR(10);',
    'ALTER TABLE notes ALTER COLUMN author SET NOT NULL;',
    'ALTER TABLE notes ADD COLUMN n INT NOT NULL;',
    'DROP TABLE notes;',
    'DELETE FROM notes;',
  ]) {
    assert.equal(checkFile('0003_bad.sql', `-- kind: expand\n${sql}`).length, 1, sql);
  }
});

test('a breaking statement in a comment does not count', () => {
  assert.deepEqual(checkFile('0003_ok.sql', '-- kind: expand\n-- later we DROP TABLE old\nCREATE TABLE x (id INT);'), []);
});

test('a contract names the first release that no longer needs what it removes', () => {
  assert.equal(checkFile('0004_drop.sql', '-- kind: contract\nALTER TABLE notes DROP COLUMN author;').length, 1);
  assert.deepEqual(checkFile('0004_drop.sql', '-- kind: contract\n-- removes-use-from: 1.2.0\nALTER TABLE notes DROP COLUMN author;'), []);
});

test('a file without a kind, or with a bad name, is refused', () => {
  assert.equal(checkFile('0005_x.sql', 'CREATE TABLE y (id INT);').length, 1);
  assert.equal(checkFile('5_x.sql', '-- kind: expand\nCREATE TABLE y (id INT);').length, 1);
  assert.equal(kindOf('-- kind: contract\n'), 'contract');
});
