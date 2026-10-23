// The message of anything thrown: an Error's message, or the thrown value itself as text.
/** @param {unknown} err */
export const messageOf = (err) => (err instanceof Error ? err.message : String(err));
