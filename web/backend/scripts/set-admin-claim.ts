/**
 * Grants (or revokes) the Firebase custom claim that the backend's
 * requireAdmin middleware accepts as an alternative to the ADMIN_UIDS
 * allowlist.
 *
 *   npm run claim-admin -- <uid>          → set   { admin: true }
 *   npm run claim-admin -- <uid> --revoke → clear the admin claim
 *
 * The target account must sign out/in (or wait for token refresh) before
 * the new claim appears in its ID token.
 */
import { fbAuth } from '../src/config/firebase';

async function main(): Promise<void> {
  const uid = process.argv[2];
  const revoke = process.argv.includes('--revoke');
  if (!uid) {
    console.error('Usage: npm run claim-admin -- <uid> [--revoke]');
    process.exit(1);
  }

  const user = await fbAuth().getUser(uid);
  const claims = { ...(user.customClaims ?? {}) };
  if (revoke) {
    delete claims.admin;
  } else {
    claims.admin = true;
  }
  await fbAuth().setCustomUserClaims(uid, claims);

  console.log(revoke ? `Removed admin claim from ${uid}` : `Granted admin claim to ${uid}`);
  console.log('The account must sign out and back in (or refresh its token) for the claim to take effect.');
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
