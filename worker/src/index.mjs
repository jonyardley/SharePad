import { escapeHtml, importPrivateKey, licenseKey, normalizeEmail } from './license.mjs';
import { sendLicenseEmail } from './email.mjs';

class StripeUnavailableError extends Error {}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/key') return await keyPage(url, env);
      if (url.pathname === '/recover') return await recoverPage(url, env);
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
  const key = await deriveKey(env, email);
  // Best-effort licence email — a Resend outage must never block the key page,
  // which is itself a complete delivery (it shows the key). No-op until
  // RESEND_API_KEY is set. NOTE: sends on each /key load, so a buyer refreshing
  // could get a duplicate; a Stripe webhook would make it exactly-once (deferred).
  try {
    await sendLicenseEmail(env, { email, key, recoverUrl: new URL('/recover', url).toString() });
  } catch {
    // swallow — delivery is best-effort; the page still shows the key
  }
  return htmlResponse(keyHtml(email, key));
}

async function recoverPage(url, env) {
  const email = url.searchParams.get('email');
  if (!email) return htmlResponse(recoverFormHtml());
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

function htmlResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
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
    It activates instantly and works offline — SharePad never phones home to check it.</p>
    <p>No need to save this page: you can recover your key anytime at
    <a href="/recover">/recover</a> with the email above — no account needed.</p>`);
}

function recoverFormHtml() {
  return page('Recover your licence', `
    <p>Enter the email you used at checkout and we'll re-derive your key.</p>
    <form method="get" action="/recover">
      <input type="email" name="email" placeholder="you@example.com" required>
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
<title>${escapeHtml(title)} — SharePad</title>
<style>
  body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 560px;
         margin: 12vh auto; padding: 0 24px; color: #1d1d1f; }
  pre { background: #f5f5f7; padding: 12px 16px; border-radius: 8px;
        overflow-x: auto; user-select: all; }
  input { font: inherit; padding: 8px 12px; }
  button { font: inherit; padding: 8px 16px; }
</style></head>
<body><h1>${escapeHtml(title)}</h1>${body}</body></html>`;
}
