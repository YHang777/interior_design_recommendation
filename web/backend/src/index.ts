import { createApp } from './app';
import { env } from './config/env';
import { firebaseConfigured } from './config/firebase';

const app = createApp();

// Port comes from process.env.PORT (Render/Docker inject it; .env may set it;
// default 4000 locally). Bind 0.0.0.0 explicitly — Render routes traffic to
// the container's interface, not loopback.
app.listen(env.port, '0.0.0.0', () => {
  console.log(`Admin API listening on http://0.0.0.0:${env.port}`);
  console.log(`  CORS origin : ${env.frontendOrigin}`);
  console.log(`  Admin UIDs  : ${env.adminUids.length} configured via ADMIN_UIDS`);
  console.log(
    `  Firebase    : ${firebaseConfigured() ? 'credentials OK' : 'NOT configured (set FIREBASE_SERVICE_ACCOUNT_JSON or SERVICE_ACCOUNT_PATH)'}`
  );
  console.log(`  Login proxy : ${env.webApiKey ? 'FIREBASE_WEB_API_KEY set' : 'FIREBASE_WEB_API_KEY missing (login will 503)'}`);
});
