import { mount } from '@vue/test-utils';
import { describe, expect, test } from 'vitest';
import ReleaseInfo from './ReleaseInfo.vue';

const props = (config: object) => ({ config: { env: 'prod', apiBaseUrl: '', flags: {}, ...config }, appVersion: '1.0.1-rc.2', appCommit: '9fb00e6' });

describe('ReleaseInfo', () => {
  test('shows the version the stage runs, beside the build it came from', () => {
    const w = mount(ReleaseInfo, { props: props({ versions: { fe: '1.0.1', be: '1.0.1' } }) });
    expect(w.text()).toContain('Env: prod · Running: 1.0.1 (built as 1.0.1-rc.2, 9fb00e6)');
    expect(w.text()).toContain('fe 1.0.1 · be 1.0.1');
  });

  test('without a deployed version it shows the build version and no release card', () => {
    const w = mount(ReleaseInfo, { props: props({}) });
    expect(w.text()).toContain('Running: 1.0.1-rc.2');
    expect(w.text()).not.toContain('Release on');
  });

  test('shows the API only when the runtime settings name it', () => {
    const versions = { fe: '1.0.1', be: '1.0.1' };
    expect(mount(ReleaseInfo, { props: props({ versions, runtime: { API_BASE_URL: 'https://api' } }) }).text()).toContain('API: https://api');
    expect(mount(ReleaseInfo, { props: props({ versions }) }).text()).not.toContain('API:');
  });
});
