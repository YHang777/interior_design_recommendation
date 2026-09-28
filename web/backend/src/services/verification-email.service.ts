import { env } from '../config/env';
import { fbAuth, firebaseConfigured } from '../config/firebase';
import { VerificationMailer } from '../lib/verification-mailer';
import type { VerifyEmailDeps } from '../routes/verify-email.routes';

/**
 * Default wiring for the `/verify-email` routes — the Node port of the Dart
 * server's `VerificationService` (`server/lib/verify_handlers.dart`).
 *
 * Same env names as the Dart server so the Render service keeps working with
 * the secrets it already has: VERIFY_TOKEN_SECRET, BREVO_API_KEY,
 * BREVO_SENDER_EMAIL/NAME, PUBLIC_BASE_URL. The Firebase half now goes
 * through firebase-admin (`updateUser(uid, { emailVerified: true })`) instead
 * of the hand-rolled Identity Toolkit client in `server/lib/firebase_admin_client.dart`.
 */
export function defaultVerifyEmailDeps(): VerifyEmailDeps {
  return {
    tokenSecret: env.verifyTokenSecret,
    mailer: new VerificationMailer({
      apiKey: env.brevoApiKey,
      senderEmail: env.brevoSenderEmail,
      senderName: env.brevoSenderName,
      publicBaseUrl: env.publicBaseUrl,
    }),
    isFirebaseConfigured: firebaseConfigured,
    setEmailVerified: async (uid: string) => {
      await fbAuth().updateUser(uid, { emailVerified: true });
    },
    log: (message: string) => console.error(message),
  };
}

/** Enough config to SEND verification emails (HMAC secret + Brevo). */
export function verificationEmailConfigured(): boolean {
  return (
    env.verifyTokenSecret.trim().length > 0 &&
    env.brevoApiKey.trim().length > 0
  );
}
