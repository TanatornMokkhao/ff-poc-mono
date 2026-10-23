// Sends one test push to a device token.
// Usage: node scripts/send-test-push.mjs <service-account.json> <fcm-token> [title] [body]
// Keep the service account file outside this repo; it can send push to every install of the app.
import { readFileSync } from 'node:fs';
import admin from 'firebase-admin';

const [saPath, token, title = 'Hello from POC', body = 'Test push'] = process.argv.slice(2);
if (!saPath || !token) {
  console.error('Usage: node scripts/send-test-push.mjs <service-account.json> <fcm-token> [title] [body]');
  process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(saPath, 'utf8'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const id = await admin.messaging().send({ token, notification: { title, body } });
console.log(`Sent: ${id}`);
