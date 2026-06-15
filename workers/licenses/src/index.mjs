import { escapeHtml, importPrivateKey, licenseKey, normalizeEmail } from './license.mjs';

class StripeUnavailableError extends Error {}

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
  return htmlResponse(keyHtml(email, await deriveKey(env, email)));
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
