// worker/scripts/generate-keys.mjs
// One-off: prints the Ed25519 keypair for SharePad licensing.
// The PRIVATE key is a secret — store it in a password manager and
// `wrangler secret put ED25519_PRIVATE_KEY`. Never commit it.
const { publicKey, privateKey } = await crypto.subtle.generateKey(
  { name: 'Ed25519' }, true, ['sign', 'verify'],
);
const raw = Buffer.from(await crypto.subtle.exportKey('raw', publicKey));
const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey));
console.log('PUBLIC  (embed in License.swift):', raw.toString('base64'));
console.log('PRIVATE (worker secret, DO NOT COMMIT):', pkcs8.toString('base64'));
