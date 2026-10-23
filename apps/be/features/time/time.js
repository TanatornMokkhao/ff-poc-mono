// GET /time: the server's clock, always in UTC.
export function time(send) {
  return send(200, { now: new Date().toISOString() });
}
