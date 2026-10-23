import { readFileSync } from 'node:fs';
import { SSMClient, GetParametersByPathCommand } from '@aws-sdk/client-ssm';

// Keys the server needs: every key in .env.example, except lines marked "optional".
export function requiredKeys(example) {
  return example
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#') && !/#[^=]*\boptional\s*$/.test(l))
    .map((l) => l.slice(0, l.indexOf('=')));
}

export function missingKeys(keys, env) {
  return keys.filter((k) => !env[k]);
}

// With SSM_PATH set (e.g. /ff-poc/staging/be/), reads every parameter under it into process.env,
// decrypting secrets, then stops the server if any .env.example key is still missing.
// Without SSM_PATH (local runs, tests) it leaves process.env as it is and checks nothing.
/** @param {{ env?: Record<string, string | undefined>, client?: Pick<SSMClient, 'send'> }} [options] */
export async function loadSettings({ env = process.env, client = new SSMClient({}) } = {}) {
  const path = env.SSM_PATH;
  if (!path) return { loaded: 0 };
  let loaded = 0;
  let NextToken;
  do {
    const page = await client.send(new GetParametersByPathCommand({ Path: path, WithDecryption: true, NextToken }));
    for (const p of page.Parameters ?? []) {
      env[p.Name.slice(p.Name.lastIndexOf('/') + 1)] = p.Value;
      loaded += 1;
    }
    NextToken = page.NextToken;
  } while (NextToken);
  const missing = missingKeys(requiredKeys(readFileSync(new URL('../../.env.example', import.meta.url), 'utf8')), env);
  if (missing.length) throw new Error(`No value under ${path} for: ${missing.join(', ')}`);
  return { loaded };
}
