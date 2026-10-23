<template>
  <p>Env: <strong>{{ config.env }}</strong> · Running: <strong>{{ running }}</strong> (built as {{ appVersion }}, {{ appCommit }})</p>
  <ion-card v-if="config.versions">
    <ion-card-header>
      <ion-card-subtitle>Release on {{ config.env }}</ion-card-subtitle>
      <ion-card-title>fe {{ config.versions.fe }} · be {{ config.versions.be }}</ion-card-title>
    </ion-card-header>
    <ion-card-content v-if="config.runtime">API: {{ config.runtime.API_BASE_URL }}</ion-card-content>
  </ion-card>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { IonCard, IonCardContent, IonCardHeader, IonCardSubtitle, IonCardTitle } from '@ionic/vue';
import type { RuntimeConfig } from '../config/config';

const props = defineProps<{ config: RuntimeConfig; appVersion: string; appCommit: string }>();
// One web build serves an rc and its prod release, so the built version is the rc's; the deploy
// writes the version the stage runs into config.json.
const running = computed(() => props.config.versions?.fe || props.appVersion);
</script>
