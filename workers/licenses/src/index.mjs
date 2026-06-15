import { escapeHtml, importPrivateKey, licenseKey, normalizeEmail } from './license.mjs';

class StripeUnavailableError extends Error {}
class EmailUnavailableError extends Error {}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/key') return await keyPage(url, env);
      if (url.pathname === '/recover') return await recoverPage(url, env, request);
      return htmlResponse(messagePage('Not found', 'Nothing to see here.'), 404);
    } catch (error) {
      if (error instanceof StripeUnavailableError) {
        return htmlResponse(messagePage(
          'Temporary problem',
          'We could not reach Stripe just now — please try again in a minute.',
        ), 502);
      }
      if (error instanceof EmailUnavailableError) {
        // A returned 5xx is not counted as a Worker error, so log it to keep
        // recover-send failures visible/alertable in observability.
        console.error('recover email send failed:', error.message);
        return htmlResponse(messagePage(
          'Could not send the email',
          'We found your purchase but could not send the email just now — please try again in a minute.',
        ), 502);
      }
      return htmlResponse(messagePage(
        'Something went wrong',
        'An unexpected error occurred on our end. If you completed checkout, contact support and we will sort it out.',
      ), 500);
    }
  },
};

async function keyPage(url, env) {
  const sessionId = url.searchParams.get('session_id');
  if (!sessionId) return htmlResponse(messagePage('Missing session', 'This link is incomplete.'), 400);
  const session = await stripeGet(`/v1/checkout/sessions/${encodeURIComponent(sessionId)}`, env);
  const email = session?.customer_details?.email;
  if (!session || session.payment_status !== 'paid' || !email) {
    return htmlResponse(messagePage(
      'Purchase not found',
      'We could not verify this checkout. If you paid, recover your key at /recover.',
    ), 404);
  }
  // The licence EMAIL is sent by the sharepad-purchase-email webhook worker
  // (exactly-once on checkout.session.completed). This page just shows the key.
  return htmlResponse(keyHtml(email, await deriveKey(env, email)));
}

async function recoverPage(url, env, request) {
  const email = url.searchParams.get('email');
  if (!email) return htmlResponse(recoverFormHtml());
  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  const { success } = await env.RECOVER_LIMITER.limit({ key: ip });
  if (!success) {
    return htmlResponse(messagePage('Slow down', 'Too many attempts — please wait a minute and try again.'), 429, { 'retry-after': '60' });
  }
  const sessions = await stripeGet(
    `/v1/checkout/sessions?customer_details[email]=${encodeURIComponent(normalizeEmail(email))}&status=complete&limit=100`,
    env,
  );
  const target = normalizeEmail(email);
  const paid = sessions?.data?.some(
    (s) => s.payment_status === 'paid'
      && normalizeEmail(s.customer_details?.email ?? '') === target,
  );
  if (!paid) {
    return htmlResponse(messagePage(
      'No purchase found',
      'No SharePad purchase matches that email. Check you used the email from checkout.',
    ), 404);
  }
  // /recover is unauthenticated — rendering the key would hand it to anyone who can
  // name a customer's email; email it instead (specs/recover-email-delivery.md).
  await sendRecoverEmail(env, email, await deriveKey(env, email));
  return htmlResponse(sentPage(email));
}

async function deriveKey(env, email) {
  return licenseKey(await importPrivateKey(env.ED25519_PRIVATE_KEY), email);
}

async function stripeGet(path, env) {
  const response = await fetch(`https://api.stripe.com${path}`, {
    headers: { Authorization: `Bearer ${env.STRIPE_API_KEY}` },
  });
  if (response.ok) return response.json();
  if (response.status === 404) return null;
  throw new StripeUnavailableError(`Stripe responded ${response.status}`);
}

function htmlResponse(body, status = 200, extraHeaders = {}) {
  return new Response(body, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      ...extraHeaders,
    },
  });
}

function keyHtml(email, key) {
  return page('Your SharePad licence', `
    <p>Thanks for buying SharePad — here's your one-time licence:</p>
    <p><strong>Email:</strong> <code>${escapeHtml(normalizeEmail(email))}</code></p>
    <p><strong>Key:</strong></p>
    <pre>${escapeHtml(key)}</pre>
    <p>In SharePad's menu-bar popover, choose <em>Enter licence…</em> and paste both.
    It takes effect straight away and works offline — SharePad never checks in with a server.</p>
    <p>No need to save this page: you can recover your key anytime at
    <a href="/recover">/recover</a> with the email above — no account needed.</p>`);
}

function sentPage(email) {
  return page('Check your inbox', `
    <p>If <code>${escapeHtml(normalizeEmail(email))}</code> bought SharePad, we've
    just emailed your licence key there — check your inbox (and spam folder).</p>
    <p>Open the email, copy the key, then in SharePad's menu-bar popover choose
    <em>Enter licence…</em> and paste it with the email above. It works offline —
    SharePad never checks in with a server.</p>
    <p>No email after a minute or two? Double-check you used your checkout email and
    try <a href="/recover">/recover</a> again.</p>`);
}

// ── Recover email (Resend) ──
async function sendRecoverEmail(env, email, key) {
  const downloadUrl = env.DOWNLOAD_URL || 'https://sharepad.co/thanks-a7f3c92b.html?owner';
  const from = env.EMAIL_FROM || 'SharePad <hello@sharepad.co>';
  const to = normalizeEmail(email);

  let response;
  try {
    response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to,
        subject: 'Your SharePad licence key',
        html: recoverEmailHtml(downloadUrl, to, key),
        text: recoverEmailText(downloadUrl, to, key),
      }),
    });
  } catch (error) {
    throw new EmailUnavailableError(error.message);
  }
  if (!response.ok) {
    throw new EmailUnavailableError(`Resend responded ${response.status}`);
  }
}

function recoverEmailHtml(downloadUrl, email, key) {
  const address = escapeHtml(normalizeEmail(email));
  const href = escapeHtml(downloadUrl);
  const font = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
  const mono = "'SF Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light only">
  <meta name="supported-color-schemes" content="light">
</head>
<body style="margin:0;padding:0;background:#F3F4FB;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F3F4FB;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="520" cellpadding="0" cellspacing="0" border="0" style="width:520px;max-width:100%;">
          <tr>
            <td style="background:#FFFFFF;border:1px solid #E6E7F2;border-radius:24px;padding:36px 32px;font-family:${font};color:#181C44;">
              <h1 style="font-size:22px;line-height:1.25;margin:0 0 12px;color:#181C44;">Your SharePad licence key</h1>
              <p style="font-size:15px;line-height:1.6;color:#4A4F78;margin:0 0 24px;">
                You asked to recover your key — here it is. You don't need to buy again;
                the same key works on every Mac.
              </p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 4px;">Email: <span style="font-family:${mono};color:#181C44;">${address}</span></p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 6px;">Key:</p>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
                <tr>
                  <td style="background:#F3F4FB;border-radius:10px;padding:12px 14px;font-family:${mono};font-size:12px;line-height:1.5;color:#181C44;word-break:break-all;">${escapeHtml(key)}</td>
                </tr>
              </table>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 24px;">
                In SharePad's menu bar, choose "Enter licence..." and paste both. It takes
                effect straight away and works offline &mdash; SharePad never checks in with a server.
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" bgcolor="#3E4CB3" style="border-radius:999px;">
                    <a href="${href}" style="display:inline-block;color:#FFFFFF;text-decoration:none;font-family:${font};font-weight:600;font-size:15px;line-height:1;padding:15px 28px;border-radius:999px;">Download SharePad</a>
                  </td>
                </tr>
              </table>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:24px 0 0;">
                Didn't ask for this? Someone entered your email on the recovery page; the key
                only reaches this inbox, so you can safely ignore it. Need a hand? Just reply.
              </p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:20px 0 0;font-family:${font};font-size:12px;color:#4A4F78;">
              <a href="https://sharepad.co" style="color:#3E4CB3;text-decoration:none;">sharepad.co</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function recoverEmailText(downloadUrl, email, key) {
  const address = normalizeEmail(email);
  return `Your SharePad licence key

You asked to recover your key -- here it is. You don't need to buy again; the same
key works on every Mac.

Email: ${address}
Key:
${key}

In SharePad's menu bar, choose "Enter licence..." and paste both. It takes effect
straight away and works offline -- SharePad never checks in with a server.

Download SharePad: ${downloadUrl}

Didn't ask for this? Someone entered your email on the recovery page; the key only
reaches this inbox, so you can safely ignore it. Need a hand? Just reply.

sharepad.co`;
}

function recoverFormHtml() {
  return page('Recover your licence', `
    <p>Already bought SharePad? You don't need to buy again. Enter the email you
    used at checkout and we'll send your key straight back.</p>
    <form method="get" action="/recover">
      <input type="email" name="email" placeholder="you@example.com" autocomplete="email" required>
      <button type="submit">Recover key</button>
    </form>`);
}

function messagePage(title, text) {
  return page(title, `<p>${escapeHtml(text)}</p>`);
}

function page(title, body) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<title>${escapeHtml(title)} — SharePad</title>
<style>
  :root {
    --bg: #F3F4FB; --card: #FFFFFF; --border: #E6E7F2;
    --ink: #181C44; --muted: #4A4F78; --accent: #3E4CB3;
    --mono: 'SF Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }
  * { box-sizing: border-box; }
  body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
         Helvetica, Arial, sans-serif; background: var(--bg); color: var(--ink);
         margin: 0; padding: 32px 16px; min-height: 100vh;
         display: flex; flex-direction: column; align-items: center;
         justify-content: center; }
  main { width: 520px; max-width: 100%; }
  .card { background: var(--card); border: 1px solid var(--border);
          border-radius: 24px; padding: 36px 32px; }
  h1 { font-size: 22px; line-height: 1.25; margin: 0 0 12px; }
  p { color: var(--muted); margin: 0 0 16px; }
  p:last-child { margin-bottom: 0; }
  strong { color: var(--ink); }
  a { color: var(--accent); }
  code { font-family: var(--mono); color: var(--ink); }
  pre { font-family: var(--mono); font-size: 13px; background: var(--bg);
        color: var(--ink); padding: 12px 14px; border-radius: 10px;
        white-space: pre-wrap; word-break: break-all; user-select: all;
        margin: 0 0 16px; }
  form { display: flex; flex-wrap: wrap; gap: 12px; margin: 24px 0 0; }
  input { flex: 1 1 220px; font: inherit; padding: 12px 14px; color: var(--ink);
          background: #fff; border: 1px solid var(--border); border-radius: 12px; }
  input:focus { outline: 2px solid var(--accent); outline-offset: 1px;
                border-color: var(--accent); }
  button { font: inherit; font-weight: 600; color: #fff; background: var(--accent);
           border: 0; border-radius: 999px; padding: 12px 26px; cursor: pointer; }
  button:hover { filter: brightness(1.06); }
  footer { text-align: center; font-size: 12px; color: var(--muted);
           margin: 20px 0 0; }
  footer a { text-decoration: none; }
</style></head>
<body><main><div class="card"><h1>${escapeHtml(title)}</h1>${body}</div>
<footer><a href="https://sharepad.co">sharepad.co</a></footer></main></body></html>`;
}
