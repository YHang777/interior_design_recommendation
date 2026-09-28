import fs from 'node:fs';
import path from 'node:path';
import { createApp, resolveAdminStaticDir } from './app';
import { env } from './config/env';
import { firebaseConfigured } from './config/firebase';
import { verificationEmailConfigured } from './services/verification-email.service';

const app = createApp();

// Port comes from process.env.PORT (Render/Docker inject it; .env may set it;
// default 4000 locally). Bind 0.0.0.0 explicitly — Render routes traffic to
// the container's interface, not loopback.
app.listen(env.port, '0.0.0.0', () => {
  console.log(`Intellar web host listening on http://0.0.0.0:${env.port}`);
  console.log('  Paths       : /admin  /admin/api/*  /api/*  /verify-email/*');
  console.log(`  CORS origin : ${env.frontendOrigin}`);
  console.log(`  Admin UIDs  : ${env.adminUids.length} configured via ADMIN_UIDS`);
  console.log(
    `  Firebase    : ${firebaseConfigured() ? 'credentials OK' : 'NOT configured (set FIREBASE_SERVICE_ACCOUNT_JSON or SERVICE_ACCOUNT_PATH)'}`
  );
  console.log(`  Login proxy : ${env.webApiKey ? 'FIREBASE_WEB_API_KEY set' : 'FIREBASE_WEB_API_KEY missing (login will 503)'}`);
  console.log(
    `  Email verify: ${verificationEmailConfigured() ? 'configured' : 'NOT configured (set VERIFY_TOKEN_SECRET + BREVO_API_KEY)'}`
  );
  const staticDir = resolveAdminStaticDir();
  const spaBuilt = fs.existsSync(path.join(staticDir, 'index.html'));
  console.log(`  Admin SPA   : ${spaBuilt ? `serving ${staticDir}` : 'NOT built (npm run build in web/frontend)'}`);
});
