import http from 'node:http';
import { handle } from './server.js';
import { loadSettings } from './settings.js';

try {
  const { loaded } = await loadSettings();
  if (loaded) console.log(`loaded ${loaded} settings from ${process.env.SSM_PATH}`);
} catch (err) {
  console.error(`settings: ${err.message}`);
  process.exit(1);
}

const port = Number(process.env.PORT || 3000);
http.createServer(handle).listen(port, () => console.log(`be ${process.env.APP_VERSION || 'dev'} on ${port}`));
