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
      <release-info :config="config" :app-version="appVersion" :app-commit="appCommit" />
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
import { onMounted } from 'vue';
import {
  IonButton, IonContent, IonHeader, IonItem, IonLabel, IonList, IonNote, IonPage, IonTextarea, IonTitle, IonToolbar,
} from '@ionic/vue';
import { useConfig } from '@/features/config/config';
import { usePush } from '@/features/push/push';
import ReleaseInfo from '@/features/release-info/ReleaseInfo.vue';

const appVersion = import.meta.env.VITE_APP_VERSION || 'local';
const appCommit = (import.meta.env.VITE_GIT_SHA || 'local').slice(0, 7);
const { config, load } = useConfig();
const { isNative, status, token, messages, listen, register } = usePush();

onMounted(async () => {
  await load();
  await listen();
});

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
