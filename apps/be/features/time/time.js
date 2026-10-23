// GET /time: the server clock, always in UTC.
/** @param {import('../../types.js').Send} send */
export function time(send) {
  return send(200, { now: new Date().toISOString() });
}
