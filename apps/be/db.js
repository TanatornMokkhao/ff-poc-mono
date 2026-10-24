import { readFileSync } from 'node:fs';

/** @typedef {import('pg').ClientConfig} DbConfig */

// The RDS certificate bundle, baked into the image (Dockerfile).
export const RDS_CA = '/etc/ssl/certs/rds-global-bundle.pem';

// Where the be finds Postgres, or null when it has none. DATABASE_URL is used as given (local runs,
// CI). Where the platform runs the be (RUNTIME set) it passes the database as parts instead, and RDS
// accepts only encrypted connections, so those come with TLS checked against the RDS bundle.
/**
 * @param {Record<string, string | undefined>} [env]
 * @param {(path: string) => string} [readCa]
 * @returns {DbConfig | null}
 */
export function dbConfig(env = process.env, readCa = (path) => readFileSync(path, 'utf8')) {
  if (env.DATABASE_URL) return { connectionString: env.DATABASE_URL };
  if (!env.RUNTIME || !env.DB_HOST || !env.DB_PASSWORD) return null;
  return {
    host: env.DB_HOST,
    port: Number(env.DB_PORT || 5432),
    database: env.DB_NAME,
    user: env.DB_USERNAME,
    password: env.DB_PASSWORD,
    ssl: { ca: readCa(env.DB_SSL_CA || RDS_CA) },
  };
}
