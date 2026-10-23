import { notes } from './notes.js';

const version = () => process.env.APP_VERSION || 'dev';

export function handle(req, res) {
  const send = (status, body) => {
    // Answers describe the running server, so a cached copy is always stale.
    res.writeHead(status, { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'cache-control': 'no-store' });
    res.end(JSON.stringify(body));
  };
  if (req.url === '/health') return send(200, { ok: true });
  if (req.url === '/version') {
    return send(200, {
      service: 'be',
      version: version(),
      commit: process.env.GIT_SHA || 'unknown',
      builtAt: process.env.BUILT_AT || 'unknown',
    });
  }
  if (req.url === '/info') {
    // Shows which environment's settings the container got, never the secret values.
    const stripe = process.env.STRIPE_SECRET_KEY || '';
    return send(200, {
      service: 'be',
      version: version(),
      env: process.env.APP_ENV || 'local',
      logLevel: process.env.LOG_LEVEL || 'info',
      dbHost: process.env.DB_HOST || null,
      dbPasswordSet: Boolean(process.env.DB_PASSWORD),
      stripeMode: stripe.startsWith('sk_live_') ? 'live' : stripe.startsWith('sk_test_') ? 'test' : 'none',
      uptimeSeconds: Math.round(process.uptime()),
    });
  }
  if (req.url === '/notes') return notes(req, send);
  return send(404, { error: 'not found', path: req.url });
}
