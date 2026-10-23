import { ref } from 'vue';
import { Capacitor } from '@capacitor/core';
import { PushNotifications } from '@capacitor/push-notifications';

export interface Message { title: string; body: string }

// Push registration, and the messages received while the app is open. Push works only in the
// native app; in a browser the status says so and nothing is registered.
export function usePush(push = PushNotifications, isNative = Capacitor.isNativePlatform()) {
  const status = ref(isNative ? 'Not registered' : 'Browser');
  const token = ref('');
  const messages = ref<Message[]>([]);

  async function listen() {
    if (!isNative) return;
    await push.addListener('registration', (t) => {
      token.value = t.value;
      status.value = 'Registered';
    });
    await push.addListener('registrationError', (e) => {
      status.value = `Error: ${e.error}`;
    });
    await push.addListener('pushNotificationReceived', (n) => {
      messages.value.unshift({ title: n.title ?? '', body: n.body ?? '' });
    });
  }

  async function register() {
    const perm = await push.requestPermissions();
    if (perm.receive !== 'granted') {
      status.value = 'Permission denied';
      return;
    }
    status.value = 'Registering...';
    await push.register();
  }

  return { isNative, status, token, messages, listen, register };
}
