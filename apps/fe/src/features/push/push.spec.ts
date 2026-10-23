import { describe, expect, test } from 'vitest';
import { usePush } from './push';

// A stand-in for the Capacitor plugin: records listeners so a test can fire them.
function fakePush(permission = 'granted') {
  const listeners: Record<string, (x: never) => void> = {};
  let registered = 0;
  const push = {
    addListener: async (name: string, fn: (x: never) => void) => { listeners[name] = fn; return { remove: async () => {} }; },
    requestPermissions: async () => ({ receive: permission }),
    register: async () => { registered++; },
  };
  return { push: push as never, fire: (name: string, x: unknown) => listeners[name](x as never), registered: () => registered, listeners };
}

describe('usePush', () => {
  test('in a browser nothing is listened to', async () => {
    const f = fakePush();
    const p = usePush(f.push, false);
    await p.listen();
    expect(p.status.value).toBe('Browser');
    expect(Object.keys(f.listeners)).toEqual([]);
  });

  test('registration stores the token; a received push goes to the top of the list', async () => {
    const f = fakePush();
    const p = usePush(f.push, true);
    expect(p.status.value).toBe('Not registered');
    await p.listen();
    f.fire('registration', { value: 'tok-1' });
    expect([p.token.value, p.status.value]).toEqual(['tok-1', 'Registered']);
    f.fire('pushNotificationReceived', { title: 'A', body: 'first' });
    f.fire('pushNotificationReceived', { title: 'B' });
    expect(p.messages.value).toEqual([{ title: 'B', body: '' }, { title: 'A', body: 'first' }]);
  });

  test('a registration error is shown', async () => {
    const f = fakePush();
    const p = usePush(f.push, true);
    await p.listen();
    f.fire('registrationError', { error: 'no FCM' });
    expect(p.status.value).toBe('Error: no FCM');
  });

  test('register asks for permission first and stops when it is refused', async () => {
    const yes = fakePush('granted');
    const p = usePush(yes.push, true);
    await p.register();
    expect([p.status.value, yes.registered()]).toEqual(['Registering...', 1]);
    const no = fakePush('denied');
    const q = usePush(no.push, true);
    await q.register();
    expect([q.status.value, no.registered()]).toEqual(['Permission denied', 0]);
  });
});
