import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { buildLicenseEmail, sendLicenseEmail } from '../src/email.mjs';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

test('buildLicenseEmail includes the normalized email + key, no emoji', () => {
  const { subject, text, html } = buildLicenseEmail({
    email: '  Buyer@Example.com ',
    key: 'ABC-key_123',
    recoverUrl: 'https://w.test/recover',
  });
  assert.equal(subject, 'Your SharePad licence');
  assert.ok(text.includes('buyer@example.com'));
  assert.ok(text.includes('ABC-key_123'));
  assert.ok(html.includes('buyer@example.com'));
  assert.ok(html.includes('ABC-key_123'));
  // no emoji anywhere in the copy
  assert.ok(!/\p{Extended_Pictographic}/u.test(subject + text + html));
});

test('sendLicenseEmail is a no-op (false) when RESEND_API_KEY is unset', async () => {
  let called = false;
  globalThis.fetch = async () => { called = true; return new Response('', { status: 200 }); };
  const sent = await sendLicenseEmail({}, { email: 'a@b.c', key: 'k', recoverUrl: 'u' });
  assert.equal(sent, false);
  assert.equal(called, false);
});

test('sendLicenseEmail POSTs to Resend with auth when configured', async () => {
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init };
    return new Response('{}', { status: 200 });
  };
  const sent = await sendLicenseEmail(
    { RESEND_API_KEY: 're_test', RESEND_FROM: 'SharePad <x@sharepad.co>' },
    { email: 'Buyer@Example.com', key: 'k', recoverUrl: 'https://w.test/recover' },
  );
  assert.equal(sent, true);
  assert.equal(captured.url, 'https://api.resend.com/emails');
  assert.equal(captured.init.headers.Authorization, 'Bearer re_test');
  const payload = JSON.parse(captured.init.body);
  assert.equal(payload.to, 'buyer@example.com');
  assert.equal(payload.from, 'SharePad <x@sharepad.co>');
  assert.equal(payload.subject, 'Your SharePad licence');
});

test('sendLicenseEmail throws on a Resend API error', async () => {
  globalThis.fetch = async () => new Response('nope', { status: 500 });
  await assert.rejects(
    () => sendLicenseEmail({ RESEND_API_KEY: 're_test' }, { email: 'a@b.c', key: 'k', recoverUrl: 'u' }),
  );
});
