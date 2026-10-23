// GET /time: the server clock, always in UTC (ISO 8601).
export function time(send) {
  return send(200, { now: new Date().toISOString() });
}
