import { escapeHtml, normalizeEmail } from './license.mjs';

export function buildLicenseEmail({ email, key, recoverUrl }) {
  const address = normalizeEmail(email);
  const subject = 'Your SharePad licence';
  const text = [
    "Thanks for buying SharePad. Here's your licence — a one-time key, yours for good.",
    '',
    `Email: ${address}`,
    'Key:',
    key,
    '',
    'Open SharePad from the menu bar, choose "Enter licence...", and paste both.',
    'It takes effect straight away and works offline — SharePad never checks in',
    'with a server.',
    '',
    `No need to keep this email: you can get your key again anytime at ${recoverUrl}`,
    'with the email above. No account, no sign-in.',
    '',
    'Thanks for the support,',
    'Jon',
    '',
    "Don't have the app yet? Download it at https://sharepad.co.",
  ].join('\n');
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"></head>
<body style="font: 16px/1.6 -apple-system, system-ui, sans-serif; color: #1d1d1f;">
  <p>Thanks for buying SharePad. Here's your licence — a <strong>one-time key,
  yours for good</strong>.</p>
  <p><strong>Email:</strong> <code>${escapeHtml(address)}</code></p>
  <p><strong>Key:</strong></p>
  <pre style="background:#f5f5f7;padding:12px 16px;border-radius:8px;overflow-x:auto;">${escapeHtml(key)}</pre>
  <p>Open SharePad from the menu bar, choose <em>Enter licence...</em>, and paste
  both. It takes effect straight away and works offline — SharePad never checks in
  with a server.</p>
  <p>No need to keep this email: you can get your key again anytime at
  <a href="${escapeHtml(recoverUrl)}">${escapeHtml(recoverUrl)}</a> with the email
  above. No account, no sign-in.</p>
  <p>Thanks for the support,<br>Jon</p>
  <p style="color:#86868b;">Don't have the app yet? Download it at
  <a href="https://sharepad.co">sharepad.co</a>.</p>
</body></html>`;
  return { subject, text, html };
}

// Best-effort licence delivery. Returns false (a no-op) until RESEND_API_KEY is
// configured, so the worker runs fine without email wired up. Throws on a Resend
// API error — callers should treat delivery as best-effort and not block on it.
export async function sendLicenseEmail(env, { email, key, recoverUrl }) {
  if (!env.RESEND_API_KEY) return false;
  const { subject, text, html } = buildLicenseEmail({ email, key, recoverUrl });
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      from: env.RESEND_FROM || 'SharePad <licences@sharepad.co>',
      to: normalizeEmail(email),
      subject,
      text,
      html,
    }),
  });
  if (!response.ok) throw new Error(`Resend responded ${response.status}`);
  return true;
}
