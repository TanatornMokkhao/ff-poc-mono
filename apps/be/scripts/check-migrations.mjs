// The expand / contract rules for migrations/*.sql (MIGRATIONS.md), checked on every pull request.
//   BASE_REF=<last release tag> node scripts/check-migrations.mjs
// BASE_REF: files that existed at that release must not change, and new ones must sort after them.
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Git paths are read relative to the app folder, wherever the repo keeps it.
const appDir = fileURLToPath(new URL('..', import.meta.url));
const NAME = /^\d{4}_[a-z0-9_]+\.sql$/;

// Statements an older release cannot live with. Each breaks code that still reads or writes the
// thing, so it may only appear in a contract migration.
/** @type {[RegExp, string][]} */
const BREAKING = [
  [/\bDROP\s+(TABLE|COLUMN|VIEW|SCHEMA|TYPE)\b/i, 'drops something'],
  [/\bRENAME\b/i, 'renames something'],
  [/\bALTER\s+COLUMN\s+\S+\s+(SET\s+DATA\s+)?TYPE\b/i, 'changes a column type'],
  [/\bSET\s+NOT\s+NULL\b/i, 'makes a column NOT NULL (old code may insert without it)'],
  // Within one statement: ADD COLUMN, no DEFAULT anywhere in it, and NOT NULL.
  [/\bADD\s+COLUMN\b(?![^;]*\bDEFAULT\b)[^;]*\bNOT\s+NULL\b/i, 'adds a NOT NULL column without a DEFAULT'],
  [/\bTRUNCATE\b/i, 'empties a table'],
  [/\bDELETE\s+FROM\b/i, 'deletes rows (data changes go in a command, not a migration)'],
];

/** @param {string} sql */
const stripComments = (sql) => sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');

/**
 * @param {string} name
 * @param {string} sql
 * @returns {string[]}
 */
export function checkFile(name, sql) {
  const problems = [];
  if (!NAME.test(name)) problems.push(`${name}: name must be NNNN_lower_snake.sql`);
  const kind = (sql.match(/^--\s*kind:\s*(expand|contract)\s*$/m) || [])[1];
  if (!kind) return [...problems, `${name}: first lines must say "-- kind: expand" or "-- kind: contract"`];
  if (kind === 'expand') {
    const body = stripComments(sql);
    for (const [re, what] of BREAKING) if (re.test(body)) problems.push(`${name}: an expand migration ${what}; that is a contract`);
  } else if (!/^--\s*removes-use-from:\s*\d+\.\d+\.\d+\s*$/m.test(sql)) {
    problems.push(`${name}: a contract must say "-- removes-use-from: X.Y.Z", the first release that no longer uses what it removes`);
  }
  return problems;
}

// gitDir: the folder whose ./migrations git reads at baseRef (the app folder; tests pass a repo of
// their own).
/**
 * @param {URL} dir
 * @param {string | undefined} baseRef
 * @param {string} [gitDir]
 * @returns {string[]}
 */
export function checkAll(dir, baseRef, gitDir = appDir) {
  const names = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const problems = names.flatMap((f) => checkFile(f, readFileSync(new URL(f, dir), 'utf8')));
  const numbers = names.map((f) => f.slice(0, 4));
  for (const n of new Set(numbers)) if (numbers.filter((x) => x === n).length > 1) problems.push(`two migrations are numbered ${n}`);
  if (baseRef) {
    /** @type {string[]} */
    let released = [];
    try {
      released = execFileSync('git', ['ls-tree', '--name-only', `${baseRef}:./migrations`], { cwd: gitDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').filter(Boolean);
    } catch {
      released = [];
    }
    for (const f of released) {
      if (!names.includes(f)) { problems.push(`${f} was released in ${baseRef} and is gone; released migrations never change`); continue; }
      const then = execFileSync('git', ['show', `${baseRef}:./migrations/${f}`], { cwd: gitDir, encoding: 'utf8' });
      if (then !== readFileSync(new URL(f, dir), 'utf8')) problems.push(`${f} was released in ${baseRef} and has changed; add a new migration instead`);
    }
    const last = released.sort().at(-1);
    for (const f of names) if (last && !released.includes(f) && f < last) problems.push(`${f} sorts before ${last}, already released; number it after`);
  }
  return problems;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const problems = checkAll(new URL('../migrations/', import.meta.url), process.env.BASE_REF);
  for (const p of problems) console.log(`::error::${p}`);
  console.log(problems.length ? `${problems.length} problem(s)` : 'migrations follow expand / contract');
  process.exitCode = problems.length ? 1 : 0;
}
