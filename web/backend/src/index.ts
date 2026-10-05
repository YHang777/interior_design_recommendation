import fs from 'node:fs';
import path from 'node:path';
import { createApp, resolveAdminStaticDir } from './app';
import { env } from './config/env';
import { firebaseConfigured } from './config/firebase';
import { verificationEmailConfigured } from './services/verification-email.service';
import { purgeDueDeletions } from './services/deletion.service';

const app = createApp();

// Account-deletion sweep — deliberately NOT in app.ts: a module-level
// interval there would keep route tests alive. Runs once at boot and every
// 15 minutes after; `purgeDueDeletions` guards itself against overlap (the
// status route kicks it fire-and-forget too, for Render free-tier sleeps).
// `.unref()` so the timer can never hold the process open by itself.
const runDeletionSweep = (): void => {
  void purgeDueDeletions()
    .then((r) => {
      if (r.purged > 0 || r.partial > 0 || r.errors > 0) {
        console.log(`[deletion sweep] purged=${r.purged} partial=${r.partial} errors=${r.errors}`);
      }
    })
    .catch((err: unknown) => {
      console.log(`[deletion sweep] skipped: ${err instanceof Error ? err.message : String(err)}`);
    });
};

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

// Server is up — start purging due deletions now, then every 15 minutes.
runDeletionSweep();
setInterval(runDeletionSweep, 15 * 60 * 1000).unref?.();
