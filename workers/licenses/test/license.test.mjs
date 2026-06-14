import assert from 'node:assert/strict';
import { test } from 'node:test';
import { base64url, escapeHtml, licenseKey, normalizeEmail } from '../src/license.mjs';

test('normalizeEmail trims and lowercases', () => {
  assert.equal(normalizeEmail('  Buyer@Example.COM \n'), 'buyer@example.com');
});

test('base64url has no padding or url-unsafe chars', () => {
  const encoded = base64url(new Uint8Array([251, 255, 190, 62, 63, 0]));
  assert.ok(!/[+/=]/.test(encoded));
});

test('licenseKey round-trips against WebCrypto verify', async () => {
  const { publicKey, privateKey } = await crypto.subtle.generateKey(
    { name: 'Ed25519' }, true, ['sign', 'verify'],
  );
  const key = await licenseKey(privateKey, '  Buyer@Example.com ');
  const padded = key.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(key.length / 4) * 4, '=');
  const signature = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  const valid = await crypto.subtle.verify(
    'Ed25519', publicKey, signature, new TextEncoder().encode('buyer@example.com'),
  );
  assert.equal(valid, true);
});

test('escapeHtml neutralises markup', () => {
  assert.equal(escapeHtml('<b>&"\'</b>'), '&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;');
});
