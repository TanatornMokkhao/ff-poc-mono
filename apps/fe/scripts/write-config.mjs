// Writes public/config.json for one stage; the web build and the apps both read it at startup.
// Keys come from .env.example. Values come from VARS_JSON (the GitHub environment's variables),
// then the process env; a local build (no STAGE) falls back to the example values.
//   STAGE=staging VARS_JSON='{"API_BASE_URL":"..."}' node scripts/write-config.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const stage = process.env.STAGE || 'local';
const vars = JSON.parse(process.env.VARS_JSON || '{}');
const entries = readFileSync('.env.example', 'utf8')
  .split('\n')
  .map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#'))
  .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]);

const runtime = {};
const missing = [];
for (const [key, example] of entries) {
  const value = vars[key] ?? process.env[key] ?? (stage === 'local' ? example : undefined);
  if (value) runtime[key] = value;
  else missing.push(key);
}
if (missing.length) {
  console.error(`No value for ${stage}: ${missing.join(', ')}. Set them as variables of the ${stage} environment in ff-poc-mono.`);
  process.exit(1);
}

const config = {
  env: stage,
  apiBaseUrl: runtime.API_BASE_URL,
  flags: { welcomeBanner: runtime.FEATURE_WELCOME_BANNER === 'true' },
  runtime,
};
writeFileSync('public/config.json', `${JSON.stringify(config, null, 2)}\n`);
console.log(`public/config.json for ${stage}: ${Object.keys(runtime).join(', ')}`);
