// Types shared by the be modules, for the type check only (JSDoc reads them; nothing runs them).
import type { IncomingMessage } from 'node:http';

/** Answers a request with a status and a JSON body. */
export type Send = (status: number, body: unknown) => void;

/** The part of a request a feature handler reads. */
export type Request = Pick<IncomingMessage, 'method' | 'on'>;
