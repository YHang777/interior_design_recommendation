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
    const link = `${this.resolveBase(baseUrlOverride)}/verify-email/confirm?token=${encodeURIComponent(token)}`;
    await this.send({
      email,
      subject: 'Verify your email — Intellar',
      html: emailHtml(link),
    });
  }

  /**
   * Deletion confirmation email — same Brevo endpoint, timeout and exception
   * type as `sendVerificationEmail`; only the link, subject and body differ.
   */
  async sendDeletionEmail({
    email,
    token,
    baseUrlOverride,
  }: {
    email: string;
    token: string;
    baseUrlOverride?: string;
  }): Promise<void> {
    const link = `${this.resolveBase(baseUrlOverride)}/account/delete/confirm?token=${encodeURIComponent(token)}`;
    await this.send({
      email,
      subject: 'Confirm account deletion — Intellar',
      html: deletionHtml(link),
    });
  }

  private resolveBase(baseUrlOverride?: string): string {
    return baseUrlOverride && baseUrlOverride.trim().length > 0
      ? baseUrlOverride.trim()
      : this.opts.publicBaseUrl;
  }

  /** Shared Brevo v3 send — one place for endpoint, timeout and errors. */
  private async send({
    email,
    subject,
    html,
  }: {
    email: string;
    subject: string;
    html: string;
  }): Promise<void> {
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
          subject,
          htmlContent: html,
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

function deletionHtml(link: string): string {
  return `
<div style="font-family:Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:32px 24px">
  <h2 style="margin:0 0 12px">Confirm account deletion</h2>
  <p style="color:#444;line-height:1.6">You asked to delete your Intellar account.
    Click the button below to confirm. This link expires in 24 hours.</p>
  <p style="margin:28px 0">
    <a href="${link}" style="background:#d64545;color:#fff;padding:12px 28px;
      border-radius:8px;text-decoration:none;font-weight:600">Confirm account deletion</a>
  </p>
  <p style="color:#444;line-height:1.6">After you confirm you have a 7-day recovery
    window: your account and personal data are permanently deleted once those
    7 days pass (your order history is kept as anonymized records). You can
    recover your account at any time during the window by signing in and
    cancelling the deletion.</p>
  <p style="color:#777;font-size:13px">Or open this link in your browser:<br>
    <a href="${link}">${link}</a><br><br>
    If you didn't ask to delete your account, you can ignore this email.</p>
</div>`;
}
