import { readFileSync } from 'node:fs';
import { SSMClient, GetParametersByPathCommand } from '@aws-sdk/client-ssm';

// Keys the server needs: every key in .env.example, except lines marked "optional".
/** @param {string} example */
export function requiredKeys(example) {
  return example
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#') && !/#[^=]*\boptional\s*$/.test(l))
    .map((l) => l.slice(0, l.indexOf('=')));
}

/**
 * @param {string[]} keys
 * @param {Record<string, string | undefined>} env
 */
export function missingKeys(keys, env) {
  return keys.filter((k) => !env[k]);
}

// With SSM_PATH set (e.g. /ff-poc/staging/be/), reads every parameter under it into process.env,
// decrypting secrets, then stops the server if any .env.example key is still missing.
// Without SSM_PATH (local runs, tests) it leaves process.env as it is and checks nothing.
// Where the platform runs the be (RUNTIME is ec2 or ecs) it sets the database and Redis addresses
// itself, and those win over the store; elsewhere the store wins, as before.
/** @param {{ env?: Record<string, string | undefined>, client?: Pick<SSMClient, 'send'> }} [options] */
export async function loadSettings({ env = process.env, client = new SSMClient({}) } = {}) {
  const path = env.SSM_PATH;
  if (!path) return { loaded: 0 };
  const platformSet = new Set(env.RUNTIME ? Object.keys(env).filter((k) => env[k]) : []);
  let loaded = 0;
  /** @type {string | undefined} */
  let NextToken;
  do {
    /** @type {import('@aws-sdk/client-ssm').GetParametersByPathCommandOutput} */
    const page = await client.send(new GetParametersByPathCommand({ Path: path, WithDecryption: true, NextToken }));
    for (const p of page.Parameters ?? []) {
      if (!p.Name) continue;
      const key = p.Name.slice(p.Name.lastIndexOf('/') + 1);
      if (platformSet.has(key)) continue;
      env[key] = p.Value;
      loaded += 1;
    }
    NextToken = page.NextToken;
  } while (NextToken);
  const missing = missingKeys(requiredKeys(readFileSync(new URL('../../.env.example', import.meta.url), 'utf8')), env);
  if (missing.length) throw new Error(`No value under ${path} for: ${missing.join(', ')}`);
  return { loaded };
}
