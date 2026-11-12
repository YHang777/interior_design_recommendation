/**
 * Replays one seller submission end-to-end through the DEPLOYED proxy:
 * reads a product's photo from Firestore, submits image-to-model exactly as
 * the app does, and prints Tripo's raw reply. An out-of-credit account
 * rejects at code 2010 before any task exists (nothing billed); a healthy
 * account creates one task (billed) whose id is printed for re-polling.
 *
 *   npm run diag-tripo-submit -- <productId>
 */
import { fbAuth, fbDb } from '../src/config/firebase';
import { env } from '../src/config/env';

const host = 'https://interior-design-recommendation.onrender.com';

async function main(): Promise<void> {
  const productId = process.argv[2];
  if (!productId) {
    console.error('Usage: npm run diag-tripo-submit -- <productId>');
    process.exit(1);
  }
  const doc = await fbDb().collection('products').doc(productId).get();
  if (!doc.exists) {
    console.error(`product ${productId} not found`);
    process.exit(1);
  }
  const product = doc.data() ?? {};
  const image = String(product.image ?? '');
  if (!image.startsWith('http')) {
    console.error(`product ${productId} has no network image`);
    process.exit(1);
  }
  console.log(`product ${productId} "${String(product.name ?? '')}" image host: ${new URL(image).host}`);

  const customToken = await fbAuth().createCustomToken('diag-tripo-submit');
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

  const resp = await fetch(`${host}/api/tripo/generation/image-to-model`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${exchanged.idToken}`,
    },
    body: JSON.stringify({
      input: image,
      texture: true,
      pbr: true,
      face_limit: 100000,
      auto_size: true,
    }),
  });
  const body = await resp.text();
  console.log(`submit HTTP ${resp.status}`);
  console.log(body.length > 1200 ? `${body.slice(0, 1200)}…` : body);
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
