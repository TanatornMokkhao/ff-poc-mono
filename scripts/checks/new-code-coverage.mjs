// Share of the lines this change adds that the app's tests run, from an lcov report.
//   node scripts/checks/new-code-coverage.mjs <be|fe> <lcov file, relative to apps/<app>>
// Fails below MIN_COVERAGE (default 80) percent, with one annotation per line no test runs.
// Only executable lines count (lcov DA lines). A changed source file the tests never load is
// missing from the report, so all its added non-blank lines count as not run. Lines in files that
// unit tests are not meant to reach (bootstrap, config, scripts run by other CI jobs) are skipped.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

const [app, lcovPath] = process.argv.slice(2);
const MIN = Number(process.env.MIN_COVERAGE || 80);
const BASE = process.env.BASE || '';
const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 64 << 20 });

const SKIP = {
  be: /^(index\.js|migrate\.js|eslint\.config\.js|scripts\/)/,
  fe: /^(src\/main\.ts|scripts\/|android\/|ios\/|public\/|[^/]+\.config\.[jt]s$)/,
};
const isSource = (p) => /\.(js|mjs|ts|vue)$/.test(p) && !/(\.test\.|\.spec\.|(^|\/)tests\/)/.test(p) && !SKIP[app].test(p);

const hasBase = () => {
  try { git('cat-file', '-e', `${BASE}^{commit}`); return true; } catch { return false; }
};
if (!BASE || !hasBase()) {
  console.log('No base commit: new-code coverage applies to pull requests and pushes only.');
  process.exit(0);
}

// Added line numbers per changed source file, paths relative to the app folder.
const added = new Map();
let file = null;
for (const line of git('diff', '-U0', '--diff-filter=ACMR', BASE, 'HEAD', '--', `apps/${app}`).split('\n')) {
  if (line.startsWith('+++ ')) {
    const p = line.slice(4).replace(/^b\//, '');
    const rel = p.slice(app.length + 6);
    file = p.startsWith(`apps/${app}/`) && isSource(rel) ? rel : null;
    if (file) added.set(file, []);
  } else if (file && line.startsWith('@@')) {
    const m = /\+(\d+)(?:,(\d+))?/.exec(line);
    const start = Number(m[1]);
    const count = m[2] === undefined ? 1 : Number(m[2]);
    for (let n = start; n < start + count; n++) added.get(file).push(n);
  }
}
if (added.size === 0) { console.log(`No ${app} source lines added.`); process.exit(0); }

// lcov: SF:<path> then DA:<line>,<hits> lines, per file.
const report = new Map();
const lcovFile = `${root}/apps/${app}/${lcovPath}`;
if (existsSync(lcovFile)) {
  const prefix = `${root.replace(/\\/g, '/')}/apps/${app}/`;
  let current = null;
  for (const line of readFileSync(lcovFile, 'utf8').split('\n')) {
    if (line.startsWith('SF:')) {
      let p = line.slice(3).replace(/\\/g, '/');
      if (p.startsWith(prefix)) p = p.slice(prefix.length);
      current = new Map();
      report.set(p, current);
    } else if (current && line.startsWith('DA:')) {
      const [n, hits] = line.slice(3).split(',').map(Number);
      current.set(n, hits);
    }
  }
}

let total = 0;
let run = 0;
const missed = [];
for (const [p, lines] of added) {
  const hits = report.get(p);
  const text = hits ? null : readFileSync(`${root}/apps/${app}/${p}`, 'utf8').split('\n');
  for (const n of lines) {
    if (hits) {
      if (!hits.has(n)) continue;
      total++;
      if (hits.get(n) > 0) run++; else missed.push([p, n, 'no test runs this line']);
    } else {
      const t = (text[n - 1] || '').trim();
      if (!t || t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
      total++;
      missed.push([p, n, 'no test loads this file']);
    }
  }
}
if (total === 0) { console.log(`No executable ${app} lines added.`); process.exit(0); }
const pct = Math.floor((run / total) * 100);
console.log(`${app}: tests run ${run} of the ${total} executable lines this change adds (${pct}%; at least ${MIN}% needed).`);
if (pct >= MIN) process.exit(0);
for (const [p, n, why] of missed.slice(0, 30)) console.log(`::error file=apps/${app}/${p},line=${n}::${why} (new-code coverage ${pct}% < ${MIN}%)`);
if (missed.length > 30) console.log(`... and ${missed.length - 30} more lines`);
process.exit(1);
