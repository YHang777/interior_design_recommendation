/**
 * Sends verification emails through the Brevo v3 transactional API
 * (https://api.brevo.com/v3/smtp/email) — faithful port of
 * `server/lib/verification_mailer.dart`. Free tier: 300 emails/day; the
 * sender address must be verified in the Brevo console.
 */

/** Safe to log; NOT shown to end users (handlers surface a generic failure). */
export class VerificationEmailException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VerificationEmailException';
  }
}

const SEND_TIMEOUT_MS = 20_000;

export interface VerificationMailerOptions {
  apiKey: string;
  senderEmail: string;
  senderName?: string;
  publicBaseUrl: string;
  /** Injectable for tests (defaults to global fetch). */
  fetchImpl?: typeof fetch;
}

export class VerificationMailer {
  constructor(private readonly opts: VerificationMailerOptions) {}

  get isConfigured(): boolean {
    return this.opts.apiKey.trim().length > 0;
  }

  /**
   * Override the configured public base URL (e.g. when the server derives
   * its own hostname from the incoming request instead of trusting env).
   */
  async sendVerificationEmail({
    email,
    token,
    baseUrlOverride,
  }: {
    email: string;
    token: string;
    baseUrlOverride?: string;
  }): Promise<void> {
    const base =
      baseUrlOverride && baseUrlOverride.trim().length > 0
        ? baseUrlOverride.trim()
        : this.opts.publicBaseUrl;
    const link = `${base}/verify-email/confirm?token=${encodeURIComponent(token)}`;
    const doFetch = this.opts.fetchImpl ?? fetch;

    let resp: Response;
    try {
      resp = await doFetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          'api-key': this.opts.apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sender: {
            name: this.opts.senderName ?? 'Intellar',
            email: this.opts.senderEmail,
          },
          to: [{ email }],
          subject: 'Verify your email — Intellar',
          htmlContent: emailHtml(link),
        }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new VerificationEmailException(`Brevo request failed: ${message}`);
    }
    if (resp.status < 200 || resp.status >= 300) {
      let snippet = '';
      try {
        snippet = await resp.text();
      } catch {
        snippet = '';
      }
      if (snippet.length > 200) snippet = snippet.slice(0, 200);
      throw new VerificationEmailException(`Brevo HTTP ${resp.status}: ${snippet}`);
    }
  }
}

function emailHtml(link: string): string {
  return `
<div style="font-family:Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:32px 24px">
  <h2 style="margin:0 0 12px">Welcome to Intellar!</h2>
  <p style="color:#444;line-height:1.6">Thanks for creating an account. Click the
    button below to verify your email address.</p>
  <p style="margin:28px 0">
    <a href="${link}" style="background:#2d6cdf;color:#fff;padding:12px 28px;
      border-radius:8px;text-decoration:none;font-weight:600">Verify my email</a>
  </p>
  <p style="color:#777;font-size:13px">Or open this link in your browser:<br>
    <a href="${link}">${link}</a><br><br>
    This link expires in 24 hours. If you didn't create an account, you can
    ignore this email.</p>
</div>`;
}
