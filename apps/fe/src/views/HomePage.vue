<template>
  <ion-page>
    <ion-header :translucent="true">
      <ion-toolbar>
        <ion-title>FF POC</ion-title>
      </ion-toolbar>
    </ion-header>

    <ion-content :fullscreen="true" class="ion-padding">
      <ion-note color="warning">
        <p><strong>BETA:</strong> new checkout, not ready for prod yet.</p>
      </ion-note>
      <ion-note v-if="config.flags.welcomeBanner" color="success">
        <p><strong>New:</strong> this banner is turned on by the FEATURE_WELCOME_BANNER setting of this stage.</p>
      </ion-note>
      <p>Env: <strong>{{ config.env }}</strong> · Running: <strong>{{ config.versions?.fe || appVersion }}</strong> (built as {{ appVersion }}, {{ appCommit }})</p>
      <ion-card v-if="config.versions">
        <ion-card-header>
          <ion-card-subtitle>Release on {{ config.env }}</ion-card-subtitle>
          <ion-card-title>fe {{ config.versions.fe }} · be {{ config.versions.be }}</ion-card-title>
        </ion-card-header>
        <ion-card-content v-if="config.runtime">API: {{ config.runtime.API_BASE_URL }}</ion-card-content>
      </ion-card>
      <p>Status: <strong>{{ status }}</strong></p>

      <ion-button expand="block" :disabled="!isNative" @click="register">Register for push</ion-button>
      <p v-if="!isNative">Push works only in the Android app, not in the browser.</p>

      <template v-if="token">
        <p>FCM token:</p>
        <ion-textarea :value="token" readonly auto-grow fill="outline" />
        <ion-button expand="block" fill="outline" @click="copyToken">Copy token</ion-button>
      </template>

      <template v-if="messages.length">
        <h3>Received</h3>
        <ion-list>
          <ion-item v-for="(m, i) in messages" :key="i">
            <ion-label>
              <h2>{{ m.title }}</h2>
              <p>{{ m.body }}</p>
            </ion-label>
          </ion-item>
        </ion-list>
      </template>
      <p class="footer-note">Shipped from ff-poc-mono: one build, promoted from staging to prod.</p>
    </ion-content>
  </ion-page>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { Capacitor } from '@capacitor/core';
import { PushNotifications } from '@capacitor/push-notifications';
import {
  IonButton, IonCard, IonCardContent, IonCardHeader, IonCardSubtitle, IonCardTitle, IonContent, IonHeader, IonItem, IonLabel, IonList, IonNote, IonPage, IonTextarea, IonTitle, IonToolbar,
} from '@ionic/vue';

interface RuntimeConfig {
  env: string;
  apiBaseUrl: string;
  flags: Record<string, boolean>;
  versions?: { be: string; fe: string };
  runtime?: Record<string, string>;
}

// env and flags arrive in config.json, baked per stage at build time; the deploy adds the versions.
const appVersion = import.meta.env.VITE_APP_VERSION || 'local';
const appCommit = (import.meta.env.VITE_GIT_SHA || 'local').slice(0, 7);
const config = ref<RuntimeConfig>({
  env: import.meta.env.VITE_API_ENV || 'local',
  apiBaseUrl: '',
  flags: {},
});
const isNative = Capacitor.isNativePlatform();
const status = ref(isNative ? 'Not registered' : 'Browser');
const token = ref('');
const messages = ref<{ title: string; body: string }[]>([]);

onMounted(async () => {
  try {
    const res = await fetch(`${import.meta.env.BASE_URL}config.json`, { cache: 'no-store' });
    if (res.ok) config.value = { ...config.value, ...(await res.json()) };
  } catch {
    // Keep the build-time defaults when config.json is missing.
  }
  if (!isNative) return;
  await PushNotifications.addListener('registration', (t) => {
    token.value = t.value;
    status.value = 'Registered';
  });
  await PushNotifications.addListener('registrationError', (e) => {
    status.value = `Error: ${e.error}`;
  });
  await PushNotifications.addListener('pushNotificationReceived', (n) => {
    messages.value.unshift({ title: n.title ?? '', body: n.body ?? '' });
  });
});

async function register() {
  const perm = await PushNotifications.requestPermissions();
  if (perm.receive !== 'granted') {
    status.value = 'Permission denied';
    return;
  }
  status.value = 'Registering...';
  await PushNotifications.register();
}

async function copyToken() {
  await navigator.clipboard.writeText(token.value);
}
</script>

<style scoped>
.footer-note {
  margin-top: 24px;
  color: var(--ion-color-medium);
  font-size: 13px;
}
</style>
