// Asserts the Ed25519 signing private key (env ED25519_PRIVATE_KEY, pkcs8 base64)
// pairs with the public key embedded in the app (License.swift). A mismatch means
// the worker would mint keys every shipped build rejects — the bug fixed in #108.
// Runs pre-deploy in both worker workflows and locally via `just check-pairing`.
// The private key is never printed; only the derived PUBLIC key is.
import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const licensePath = join(repoRoot, 'Sources/SharePad/Licensing/License.swift');

function fail(msg) {
  console.error(`✗ key-pairing check failed: ${msg}`);
  process.exit(1);
}

const pkcs8 = (process.env.ED25519_PRIVATE_KEY ?? '').trim();
if (!pkcs8) fail('ED25519_PRIVATE_KEY is not set.');

const source = readFileSync(licensePath, 'utf8');
const embedded = source.match(/publicKeyBase64\s*=\s*"([^"]+)"/)?.[1];
if (!embedded) fail(`could not find publicKeyBase64 in ${licensePath}`);

let derivedPub;
try {
  const priv = crypto.createPrivateKey({
    key: Buffer.from(pkcs8, 'base64'),
    format: 'der',
    type: 'pkcs8',
  });
  const jwk = crypto.createPublicKey(priv).export({ format: 'jwk' });
  derivedPub = Buffer.from(jwk.x.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('base64');
} catch (e) {
  fail(`ED25519_PRIVATE_KEY is not valid pkcs8 base64 (${e.message}).`);
}

if (derivedPub !== embedded) {
  fail(
    'the signing key does not pair with the app.\n'
    + `  embedded (License.swift): ${embedded}\n`
    + `  derived  (from secret)  : ${derivedPub}\n`
    + '  Fix: re-embed the derived public key in License.swift, or set the correct '
    + 'ED25519_PRIVATE_KEY secret. Both workers and the app must share one keypair.',
  );
}

console.log(`✓ signing key pairs with the app's embedded public key (${embedded}).`);
