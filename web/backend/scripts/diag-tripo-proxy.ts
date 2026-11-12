/**
 * Probes the DEPLOYED Tripo proxy's key health without spending a task.
 *
 *   npm run diag-tripo-proxy
 *
 * Mints a short-lived Firebase ID token (local service account), then GETs
 * /api/tripo/tasks/<fake> through the deployed host. The proxy forwards the
 * query to Tripo with ITS key, so the reply tells us what that key is worth:
 * 401/403 auth-style → the deployed key is dead (rotate on Render);
 * task-not-found-ish → the key works and failures are credit/quota;
 * anything else → printed verbatim for reading.
 */
import { fbAuth } from '../src/config/firebase';
import { env } from '../src/config/env';

const host = 'https://interior-design-recommendation.onrender.com';

async function main(): Promise<void> {
  const customToken = await fbAuth().createCustomToken('diag-tripo-probe');
  const exchange = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${env.webApiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    }
  );
  const exchanged = (await exchange.json()) as { idToken?: string; error?: unknown };
  if (!exchanged.idToken) {
    console.error('token exchange failed:', JSON.stringify(exchanged.error ?? exchanged));
    process.exit(1);
  }

  const resp = await fetch(`${host}/api/tripo/tasks/task_diag_probe_invalid`, {
    headers: { Authorization: `Bearer ${exchanged.idToken}` },
  });
  const body = await resp.text();
  console.log(`HTTP ${resp.status}`);
  console.log(body.length > 600 ? `${body.slice(0, 600)}…` : body);
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
