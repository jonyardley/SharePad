import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import worker from '../src/index.mjs';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

async function generateEnv() {
  const { privateKey } = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey)).toString('base64');
  return {
    ED25519_PRIVATE_KEY: pkcs8,
    STRIPE_API_KEY: 'rk_test_stub',
    RESEND_API_KEY: 're_test_stub',
    RECOVER_LIMITER: { limit: async () => ({ success: true }) },
  };
}

// /key calls only Stripe; /recover calls Stripe then Resend. Route by host so a
// single stub serves both and we can capture what /recover tried to email.
function stubStripe(status, body, { resendStatus = 200 } = {}) {
  const sent = [];
  globalThis.fetch = async (url, init) => {
    if (String(url).includes('api.resend.com')) {
      sent.push(JSON.parse(init.body));
      return new Response('{}', { status: resendStatus });
    }
    return new Response(JSON.stringify(body), { status });
  };
  return sent;
}

test('unknown route is 404 with no-store', async () => {
  const response = await worker.fetch(new Request('https://w.test/nope'), await generateEnv());
  assert.equal(response.status, 404);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('/key without session_id is 400', async () => {
  const response = await worker.fetch(new Request('https://w.test/key'), await generateEnv());
  assert.equal(response.status, 400);
});

test('/key with paid session shows the key', async () => {
  stubStripe(200, { payment_status: 'paid', customer_details: { email: 'Buyer@Example.com' } });
  const response = await worker.fetch(new Request('https://w.test/key?session_id=cs_x'), await generateEnv());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('buyer@example.com'));
  assert.ok(/<pre>[A-Za-z0-9_-]{86}<\/pre>/.test(html));
});

test('/key with unpaid session is 404', async () => {
  stubStripe(200, { payment_status: 'unpaid', customer_details: { email: 'a@b.c' } });
  const response = await worker.fetch(new Request('https://w.test/key?session_id=cs_x'), await generateEnv());
  assert.equal(response.status, 404);
});

test('stripe outage is a 502, not purchase-not-found', async () => {
  stubStripe(500, { error: 'boom' });
  const response = await worker.fetch(new Request('https://w.test/key?session_id=cs_x'), await generateEnv());
  assert.equal(response.status, 502);
});

test('/recover with no email renders the form', async () => {
  const response = await worker.fetch(new Request('https://w.test/recover'), await generateEnv());
  assert.equal(response.status, 200);
  assert.ok((await response.text()).includes('<form'));
});

test('/recover with paid history emails the key and never shows it', async () => {
  const sent = stubStripe(200, { data: [{ payment_status: 'paid', customer_details: { email: 'buyer@example.com' } }] });
  const response = await worker.fetch(new Request('https://w.test/recover?email=Buyer@Example.com'), await generateEnv());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('buyer@example.com'));
  assert.ok(/inbox/i.test(html));
  // The key must reach the inbox, not the page.
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'Buyer@Example.com');
  assert.ok(/[A-Za-z0-9_-]{86}/.test(sent[0].text));
  assert.ok(!/[A-Za-z0-9_-]{86}/.test(html));
});

test('/recover returns 502 and no key when the email send fails', async () => {
  const sent = stubStripe(
    200,
    { data: [{ payment_status: 'paid', customer_details: { email: 'buyer@example.com' } }] },
    { resendStatus: 500 },
  );
  const response = await worker.fetch(new Request('https://w.test/recover?email=buyer@example.com'), await generateEnv());
  assert.equal(response.status, 502);
  const html = await response.text();
  assert.equal(sent.length, 1);
  assert.ok(!/[A-Za-z0-9_-]{86}/.test(html));
});

test('/recover rejects a paid session whose email does not match', async () => {
  stubStripe(200, { data: [{ payment_status: 'paid', customer_details: { email: 'someone-else@x.com' } }] });
  const response = await worker.fetch(new Request('https://w.test/recover?email=victim@y.z'), await generateEnv());
  assert.equal(response.status, 404);
});

test('/recover with no purchases is 404', async () => {
  stubStripe(200, { data: [] });
  const response = await worker.fetch(new Request('https://w.test/recover?email=x@y.z'), await generateEnv());
  assert.equal(response.status, 404);
});

test('/recover is rate-limited with 429 when the limiter denies', async () => {
  const env = { ...(await generateEnv()), RECOVER_LIMITER: { limit: async () => ({ success: false }) } };
  const response = await worker.fetch(new Request('https://w.test/recover?email=x@y.z'), env);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '60');
});

test('a malformed signing key is a 500, not a 502', async () => {
  stubStripe(200, { payment_status: 'paid', customer_details: { email: 'a@b.c' } });
  const env = { ED25519_PRIVATE_KEY: 'not-valid-pkcs8', STRIPE_API_KEY: 'rk_test_stub' };
  const response = await worker.fetch(new Request('https://w.test/key?session_id=cs_x'), env);
  assert.equal(response.status, 500);
});

test('query email is escaped in output', async () => {
  stubStripe(200, { data: [{ payment_status: 'paid', customer_details: { email: '<img src=x>@y.z' } }] });
  const response = await worker.fetch(new Request('https://w.test/recover?email=' + encodeURIComponent('<img src=x>@y.z')), await generateEnv());
  const html = await response.text();
  assert.ok(!html.includes('<img'));
});
