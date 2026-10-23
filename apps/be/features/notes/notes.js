import pg from 'pg';
import { messageOf } from '../../errors.js';

/** @typedef {import('../../types.js').Send} Send */
/** @typedef {import('../../types.js').Request} Request */

/** @type {pg.Pool | undefined} */
let pool;
/** @returns {pg.Pool} */
const db = () => (pool ??= new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5 }));

/**
 * @param {Request} req
 * @returns {Promise<{ body?: unknown, author?: unknown }>}
 */
const readBody = (req) =>
  new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (/** @type {Buffer} */ c) => (raw += c));
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error('body is not JSON'));
      }
    });
    req.on('error', reject);
  });

// GET lists the 20 newest notes; POST {body, author?} adds one.
/**
 * @param {Request} req
 * @param {Send} send
 */
export async function notes(req, send) {
  if (!process.env.DATABASE_URL) return send(503, { error: 'no database configured' });
  try {
    if (req.method === 'GET') {
      const { rows } = await db().query('SELECT id, body, author, created_at FROM notes ORDER BY id DESC LIMIT 20');
      return send(200, rows);
    }
    if (req.method === 'POST') {
      const { body, author = null } = await readBody(req);
      if (typeof body !== 'string' || !body) return send(400, { error: 'body is required' });
      const { rows } = await db().query('INSERT INTO notes (body, author) VALUES ($1, $2) RETURNING id, body, author, created_at', [body, author]);
      return send(201, rows[0]);
    }
    return send(405, { error: 'GET or POST' });
  } catch (err) {
    const message = messageOf(err);
    return send(message === 'body is not JSON' ? 400 : 500, { error: message });
  }
}
